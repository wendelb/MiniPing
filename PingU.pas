unit PingU;

interface

uses
  Windows, WinSock, SysUtils;

function Ping(const Host: string; out ResultLine: String): Integer;

implementation

{$REGION 'ICMP related functions and types'}

type
  PIPOptionInformation = ^TIPOptionInformation;

  TIPOptionInformation = record
    Ttl: Byte; // time to live
    Tos: Byte; // type of service
    Flags: Byte; // ip header flags
    OptionsSize: Byte; // size in bytes of options data
    OptionsData: ^Byte; // pointer to options data
  end;

  ICMP_ECHO_REPLY = record
    Address: in_addr; // replying address
    Status: ULONG; // reply ip_status
    RoundTripTime: ULONG; // rtt in milliseconds
    DataSize: ULONG; // reply data size in bytes
    Reserved: ULONG; // reserved for system use
    Data: Pointer; // pointer to the reply data
    Options: PIPOptionInformation; // reply options
  end;

  PICMP_ECHO_REPLY = ^ICMP_ECHO_REPLY;

function IcmpCreateFile: THandle; stdcall; external 'icmp.dll';
function IcmpCloseHandle(icmpHandle: THandle): Boolean; stdcall; external 'icmp.dll';
function IcmpSendEcho(icmpHandle: THandle; DestinationAddress: in_addr; RequestData: Pointer; RequestSize: Word; RequestOptions: PIPOptionInformation; ReplyBuffer: Pointer; ReplySize: DWORD; Timeout: DWORD): DWORD; stdcall; external 'icmp.dll';

{$ENDREGION}
{$REGION 'Host + IP to Internal representation'}

function LookupIP(const Hostname: AnsiString; var IPv4: in_addr): Boolean;
var
  HostInfo: PHostEnt;
begin
  // Default Result Values
  Result := FALSE;
  IPv4.S_addr := -1;

  // Do the Lookup
  if (Hostname <> '') then
  begin
    HostInfo := GetHostByName(PAnsiChar(Hostname));
  end
  else
  begin
    // Empty String means localhost
    HostInfo := GetHostByName(NIL);
  end;

  if HostInfo <> nil then
  begin
    // Fetch first address from result
    IPv4.S_addr := PInAddr(HostInfo^.h_addr_list^)^.S_addr;
    Result := True;
  end;
end;

{$ENDREGION}
{$REGION 'Error Messages' }

const
  IP_STATUS_BASE = 11000;
  IP_SUCCESS = 0;
  IP_BUF_TOO_SMALL = IP_STATUS_BASE + 1;
  IP_DEST_NET_UNREACHABLE = IP_STATUS_BASE + 2;
  IP_DEST_HOST_UNREACHABLE = IP_STATUS_BASE + 3;
  IP_DEST_PROT_UNREACHABLE = IP_STATUS_BASE + 4;
  IP_DEST_PORT_UNREACHABLE = IP_STATUS_BASE + 5;
  IP_NO_RESOURCES = IP_STATUS_BASE + 6;
  IP_BAD_OPTION = IP_STATUS_BASE + 7;
  IP_HW_ERROR = IP_STATUS_BASE + 8;
  IP_PACKET_TOO_BIG = IP_STATUS_BASE + 9;
  IP_REQ_TIMED_OUT = IP_STATUS_BASE + 10;
  IP_BAD_REQ = IP_STATUS_BASE + 11;
  IP_BAD_ROUTE = IP_STATUS_BASE + 12;
  IP_TTL_EXPIRED_TRANSIT = IP_STATUS_BASE + 13;
  IP_TTL_EXPIRED_REASSEM = IP_STATUS_BASE + 14;
  IP_PARAM_PROBLEM = IP_STATUS_BASE + 15;
  IP_SOURCE_QUENCH = IP_STATUS_BASE + 16;
  IP_OPTION_TOO_BIG = IP_STATUS_BASE + 17;
  IP_BAD_DESTINATION = IP_STATUS_BASE + 18;
  IP_GENERAL_FAILURE = IP_STATUS_BASE + 50;

function ErrorToText(const ErrorCode: Integer): String;
begin
  case ErrorCode of
    IP_BUF_TOO_SMALL:
      Result := 'IP_BUF_TOO_SMALL';
    IP_DEST_NET_UNREACHABLE:
      Result := 'IP_DEST_NET_UNREACHABLE';
    IP_DEST_HOST_UNREACHABLE:
      Result := 'IP_DEST_HOST_UNREACHABLE';
    IP_DEST_PROT_UNREACHABLE:
      Result := 'IP_DEST_PROT_UNREACHABLE';
    IP_DEST_PORT_UNREACHABLE:
      Result := 'IP_DEST_PORT_UNREACHABLE';
    IP_NO_RESOURCES:
      Result := 'IP_NO_RESOURCES';
    IP_BAD_OPTION:
      Result := 'IP_BAD_OPTION';
    IP_HW_ERROR:
      Result := 'IP_HW_ERROR';
    IP_PACKET_TOO_BIG:
      Result := 'IP_PACKET_TOO_BIG';
    IP_REQ_TIMED_OUT:
      Result := 'IP_REQ_TIMED_OUT';
    IP_BAD_REQ:
      Result := 'IP_BAD_REQ';
    IP_BAD_ROUTE:
      Result := 'IP_BAD_ROUTE';
    IP_TTL_EXPIRED_TRANSIT:
      Result := 'IP_TTL_EXPIRED_TRANSIT';
    IP_TTL_EXPIRED_REASSEM:
      Result := 'IP_TTL_EXPIRED_REASSEM';
    IP_PARAM_PROBLEM:
      Result := 'IP_PARAM_PROBLEM';
    IP_SOURCE_QUENCH:
      Result := 'IP_SOURCE_QUENCH';
    IP_OPTION_TOO_BIG:
      Result := 'IP_OPTION_TOO_BIG';
    IP_BAD_DESTINATION:
      Result := 'IP_BAD_DESTINATION';
    IP_GENERAL_FAILURE:
      Result := 'IP_GENERAL_FAILURE';

  else
    Result := 'Unknown Error';
  end;
end;

// Returns the last Win32 error, in string format. Returns an empty string if there is no error.
// Translated from: https://stackoverflow.com/questions/1387064/how-to-get-the-error-message-from-the-error-code-returned-by-getlasterror
function GetErrorAsString(const Error: DWORD): string;
var
  messageBuffer: PChar;
begin
  if (Error = 0) then
  begin
    // No error -> empty string
    Result := '';
  end
  else
  begin
    messageBuffer := nil;
    FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS, nil, Error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), @messageBuffer, 0, nil);
    Result := messageBuffer;
  end;
end;

{$ENDREGION}

function Ping(const Host: string; out ResultLine: String): Integer;
var
  ip: in_addr;
  ICMPFile: THandle;
  SendData: array [0 .. 31] of AnsiChar;
  ReplyBuffer: PICMP_ECHO_REPLY;
  ReplySize: DWORD;
  NumResponses: DWORD;
begin
  SendData := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  if LookupIP(AnsiString(Host), ip) then
  begin
    ICMPFile := IcmpCreateFile;
    if ICMPFile <> INVALID_HANDLE_VALUE then
      try
        ReplySize := SizeOf(ICMP_ECHO_REPLY) + SizeOf(SendData);
        GetMem(ReplyBuffer, ReplySize);
        try
          NumResponses := IcmpSendEcho(ICMPFile, ip, @SendData, SizeOf(SendData), nil, ReplyBuffer, ReplySize, 1000);
          if (NumResponses <> 0) then
          begin
            ResultLine := 'Received Response in ' + IntToStr(ReplyBuffer.RoundTripTime) + ' ms';
            Result := 0;
          end
          else
          begin
            ResultLine := 'Error: ' + ErrorToText(GetLastError());
            Result := 1;
          end;
        finally
          FreeMem(ReplyBuffer);
        end;
      finally
        IcmpCloseHandle(ICMPFile);
      end
    else
    begin
      ResultLine := 'IcmpCreateFile returned error: ' + GetErrorAsString(GetLastError());
      Result := 2;
    end;
  end
  else
  begin
    // Address seems invalid
    ResultLine := 'Cannot lookup address: ' + GetErrorAsString(GetLastError());
    Result := 3;
  end;
end;

{$REGION 'Initialization'}
// Initialize WSA for use wich ICMP

var
  WSAData: TWSAData;

initialization
  WSAStartup(MAKEWORD(2, 2), WSAData);

finalization
  WSACleanup();

{$ENDREGION}

end.