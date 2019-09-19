import strutils
import system
import tables
import options
import streams

## Object for storing program state

type State* = object
  compile: bool 
  tokens*: seq[string]
  token_idx*: int
  stack*: seq[int]
  error: string

proc `$`*(s: State): string =
  return s.error & ": " & ($s.stack)[2..^2];

proc `peek`*(s: State): Option[int] =
  if s.stack.len > 0:
    return some(s.stack[^1])

proc `pop`*(s: var State): Option[int] =
  if s.stack.len > 0:
    result = some(s.stack[^1])
    s.stack = s.stack[0 .. ^2]

proc `put`*(s: var State; n: int): int =
  result = n
  s.stack.add(n)

## Bark primitives

proc barkPlus(s: var State): Option[int] =
  let a: Option[int] = s.pop
  let b: Option[int] = s.pop
  if a.isSome and b.isSome:
    s.error = "ok"
    return some(s.put(a.get + b.get))
  elif a.isSome and not b.isSome:
    s.error = "error"
    return some(s.put(a.get))
  else:
    s.error = "error"
    return none(int)

proc barkPrint(s: var State): Option[int] =
  let a: Option[int] = s.pop
  if a.isSome:
    s.error = "ok"
    echo a.get
    return some(a.get)
  else:
    s.error = "error"

proc barkMinus(s: var State): Option[int] =
  let a: Option[int] = s.pop
  let b: Option[int] = s.pop
  if a.isSome and b.isSome:
    s.error = "ok"
    return some(s.put(a.get - b.get))
  elif a.isSome and not b.isSome:
    s.error = "error"
    return some(s.put(a.get))
  else:
    s.error = "error"
    return none(int)

proc barkBranch(s: var State): Option[int] =
  try:
    s.error = "ok"
    s.token_idx = parseint(s.tokens[s.token_idx+1])-1
  except ValueError:
    s.error = "error"
    echo "Error: token following branch should be integer."
    discard

proc barkZeroBranch(s: var State): Option[int] =
  let a: Option[int] = s.pop
  if a.isSome:
    if a.get == 0:
      try:
        s.error = "ok"
        s.token_idx = parseint(s.tokens[s.token_idx+1])-1
      except ValueError:
        s.error = "error"
        echo "Error: tokens following branch? should be integers."
        discard
    else:
      try:
        s.error = "ok"
        s.token_idx = parseInt(s.tokens[s.token_idx+2])-1
      except ValueError:
        s.error = "error"
        echo "Error: tokens following branch? should be integers."
        discard

proc barkHalt(s: var State): Option[int] =
  GC_fullCollect()
  quit()


let dictionary = {"+":barkPlus,
                  "-":barkMinus,
                  "print":barkPrint,
                  "branch":barkBranch,
                  "branch?":barkZeroBranch,
                  "halt":barkHalt}.toTable

proc barkNextTokenEffect(s: var State) =
  if s.token_idx >= s.tokens.len():
    return
  if dictionary.hasKey(s.tokens[s.token_idx]):
    discard dictionary[s.tokens[s.token_idx]](s)
  else:
    try:
      s.error = "ok"
      discard s.put(parseInt(s.tokens[s.token_idx]))
    except ValueError:
      echo "Error: undefined word."
      discard
  s.token_idx = s.token_idx + 1

proc barkRunProgram(s: var State) =
  while s.token_idx < s.tokens.len():
    barkNextTokenEffect(s)

when isMainModule:
  import docopt

  let doc = """
bark 0.1.0 by Luka Hadzi-Djokic

Usage:
  bark
  bark --help
  bark (-v | --version)

Options:
  --help           Show this screen.
  -v --version     Show version.
"""
  let args = docopt(doc, version = "bark 0.1.0")


  var state: State
  state.tokens = @[]
  state.token_idx = 0
  state.stack = @[]
  state.error = "ok"
  var input_string: string
  while true:
    stdout.write "> "
    var stdin_stream = newFileStream(stdin)
    input_string = stdin_stream.readLine
    state.tokens = @[]
    state.token_idx = 0
    for token in input_string.splitWhitespace():
      state.tokens.add(token)
    barkRunProgram(state)
    stdout.writeln $state

