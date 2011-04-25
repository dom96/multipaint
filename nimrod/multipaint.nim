import sdl, graphics, colors
import sockets, os, parseutils, posix, strutils
import times, math

type
  TCommand = enum
    CONNECT = 1, DISCONNECT, MESSAGE, DRAW, ERASE, PINGPONG

  TScreen = object
    mainSurface: graphics.PSurface

const
  winWidth = 800
  winHeight = 600
  drawColors = [colBlack, colGray, colRed, colLightGreen, colBlue, colYellow, colFuchsia, colCyan, colWhite]
  nickname = "dom96"

# Drawing
proc drawCurrentColor(screen: TScreen, currentColor: int) =
  var r: graphics.TRect = (winWidth-20, winHeight-20, 20, 20)
  screen.mainSurface.fillRect(r, drawColors[currentColor])

# Misc
proc changeColor(screen: TScreen, currentColor: var int, down: bool) =
  if down:
    if currentColor == 0:
      currentColor = 7
    else:
      dec(currentColor)
  else:
    if currentColor == 7:
      currentColor = 0
    else:
      inc(currentColor)
  screen.drawCurrentColor(currentColor)

proc drawDot(screen: TScreen, x, y: int, color: int) =
  if x+1 <% screen.mainSurface.w and y+1 <% screen.mainSurface.h:
    screen.mainSurface.setPixel(x, y, drawColors[color])
    screen.mainSurface.setPixel(x+1, y, drawColors[color])
    screen.mainSurface.setPixel(x, y+1, drawColors[color])
    screen.mainSurface.setPixel(x+1, y+1, drawColors[color])

proc drawPacketsLen(screen: TScreen, packets: int) =
  var text = $packets & " packets"
  var rect = textBounds(text)
  var rectToFill = (5, 5+rect.height, rect.width+10, rect.height)
  screen.mainSurface.fillRect(rectToFill, colWhite)
  screen.mainSurface.drawText((5, 5+rect.height), text)

# Networking
proc openConnection(server: string): TSocket = 
  echo("Connecting to: " & server)
  result = socket(sockets.AF_INET, sockets.SOCK_DGRAM, sockets.IPPROTO_UDP)
  if fcntl(cint(result), F_SETFL, O_NONBLOCK) == -1:
    OSError()
  if result == InvalidSocket:
    OSError()
  result.connect(server, TPort(5303))

proc getCmd(line: string): TCommand =
  case line[1]
  of '\1':
    return CONNECT
  of '\2': 
    return DISCONNECT
  of '\3':
    return MESSAGE
  of '\4':
    return DRAW
  of '\5':
    return ERASE
  of '\6':
    return PINGPONG
  else:
    echo("Invalid byte: ", repr(line[1]))

proc toStringBytes(line: string): string =
  result = ""
  for i in items(line):
    result.add("'\\" & $int(i) & "', ")

proc parse(screen: TScreen, line: string) =
  var command = getCmd(line)
  case command
  of Connect:
    var ip = ""
    if line.parseUntil(ip, {'\0'}, 2) == 0:
      echo("WARNING: Incorrect connect line. Got: ", toStringBytes(line))
    else:
      echo("Connected: ", ip)
  of DRAW, ERASE:
    var i = 2
    var ip = ""
    i = i + line.parseUntil(ip, {'\0'}, i) + 1
    if i == 0:
        echo("Unable to get nickname.")
    while (i+5) < line.len():
      var x = int(line[i]) shl 8 or int(line[i+1])
      i = i + 2
      var y = int(line[i]) shl 8 or int(line[i+1])
      i = i + 2
      var color = int(line[i]) shl 8 or int(line[i+1])
      i = i + 2
      if command == DRAW:
        screen.drawDot(x, y, color)
      else:
        screen.drawDot(x, y, 8)

  of PINGPONG:
    var time = parseFloat(line.copy(2, line.len()-1))
    var newTime = epochTime()
    var text = $round((newTime - time) * 1000.0) & "ms"
    var rect = textBounds(text)
    var rectToFill = (5, 5, rect.width+10, rect.height)
    screen.mainSurface.fillRect(rectToFill, colWhite)
    screen.mainSurface.drawText((5, 5), text)
  
  else: echo("Not implemented")

proc nonBlockingRecv(sock: TSocket, line: var string): int =
  var bufSize = 65536
  line = newString(bufSize)
  var bytesRead = recv(sock, cstring(line), bufSize-1)

  if bytesRead == -1:
    return -1
  line[bytesRead] = '\0'
  setLen(line, bytesRead)
  return bytesRead

proc nonBlockingRecvFrom(sock: TSocket, line: var string): int =
  var bufSize = 65536
  line = newString(bufSize)
  var bytesRead = recvFrom(cint(sock), cstring(line), bufSize-1, MSG_OOB, nil, nil)

  if bytesRead == -1:
    return -1
  line[bytesRead] = '\0'
  setLen(line, bytesRead)
  return bytesRead

proc sendDraw(sock: TSocket, cx, cy: int, color: int) =
  var x = cx shr 8
  var x1 = cx and 0xFF
  var y = cy shr 8
  var y1 = cy and 0xFF
  sock.send("\x00\x04$1$2$3$4\0$5" % 
            [$char(x), $char(x1), $char(y), $char(y1), $char(color)])

proc sendPing(sock: TSocket) =
  var time = epochTime()
  sock.send("\x00\x06" & formatFloat(time))

proc sendErase(sock: TSocket, cx, cy: int) =
  var x = cx shr 8
  var x1 = cx and 0xFF
  var y = cy shr 8
  var y1 = cy and 0xFF
  sock.send("\x00\x05$1$2$3$4" % [$char(x), $char(x1), $char(y), $char(y1)])

when isMainModule:
  echo init(INIT_EVERYTHING)
  initDefaultFont(name="/usr/share/fonts/truetype/ttf-dejavu/DejaVuSansMono.ttf", color = colRed)
  var ver: TVersion
  VERSION(ver)
  echo("Running sdl version: " & $ver.major & "." & $ver.minor & "." & $ver.patch)
  WM_SetCaption("Multipaint by dom96.", "")
  
  var screen: TScreen
  screen.mainSurface = newScreenSurface(winWidth, winHeight)
  var r: graphics.TRect = (0, 0, winWidth+1, winHeight+1)

  # Fill screen with white
  screen.mainSurface.fillRect(r, colWhite)

  # Connect to the server
  var sock = openConnection(paramStr(1))
  var socks = @[sock]
  sock.send("\x00\x01" & nickname & "\x00")

  var mouseDownLeft = false
  var mouseDownRight = false
  var latestPing = epochTime() # In miliseconds
  var packetsRecv = 0
  var currentColor = 0
  screen.drawCurrentColor(currentColor)

  while True:
    # Poll socket
    var line: string
    if sock.nonBlockingRecv(line) > 0:
      screen.parse($line)
      inc(packetsRecv)
      screen.drawPacketsLen(packetsRecv)
    
    var time = epochTime()
    if time - latestPing > 3.0:
      echo("PING, ", formatFloat(time - latestPing))
      sock.sendPing()
      latestPing = time
    
    # Poll sdl events
    var event: SDL.TEvent
    if SDL.PollEvent(addr(event)) == 1:
      case event.kind:
      of sdl.QuitEv:
        break
      of sdl.MouseButtonDown:
        var mb = EvMouseButton(addr(event))
        case int(mb.button)
        of BUTTON_LEFT:
          var x = int(mb.x)
          var y = int(mb.y)
          sock.sendDraw(x, y, currentColor)
          mouseDownLeft = True
        of BUTTON_RIGHT:
          var x = int(mb.x)
          var y = int(mb.y)
          sock.sendErase(x, y)
          mouseDownRight = True
        of BUTTON_WHEELDOWN:
          screen.changeColor(currentColor, true)
        of BUTTON_WHEELUP:
          screen.changeColor(currentColor, false)
        else: nil
      of sdl.MouseButtonUp:
        mouseDownLeft = False
        mouseDownRight = false
      of sdl.MouseMotion:
        if mouseDownLeft:
          var x = int(EvMouseMotion(addr(event)).x)
          var y = int(EvMouseMotion(addr(event)).y)
          sock.sendDraw(x, y, currentColor)
        elif mouseDownRight:
          var x = int(EvMouseMotion(addr(event)).x)
          var y = int(EvMouseMotion(addr(event)).y)
          sock.sendErase(x, y)
      else:
        #echo(event.kind)
    
    SDL.UpdateRect(screen.mainSurface.s, int32(0), int32(0), int32(winWidth), int32(winHeight))
    
  SDL.Quit()

