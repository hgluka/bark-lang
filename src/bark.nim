{.experimental: "codeReordering".}
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
  new_word*: seq[string]

proc `empty`*(s: var State): State =
  s.compile = false
  s.tokens = @[]
  s.token_idx = 0
  s.stack = @[]
  s.error = "ok"
  s.new_word = @[]
  return s

proc `$`*(s: State): string =
  return s.error & ": " & ($s.stack)[2..^2]

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

proc barkMakeCompatible(f: proc (s: var State) : Option[int]): proc (s: var State): Option[int] {.closure.} =
  return proc (s: var State): Option[int] {.closure.} =
    return f(s)

proc barkMakeWord(tokens: seq[string]): proc (s: var State): Option[int] {.closure.} =
  var new_state: State
  discard new_state.empty
  new_state.tokens = tokens
  return proc (s: var State): Option[int] {.closure.} =
    new_state.stack = s.stack
    barkRunProgram(new_state)
    s.stack = new_state.stack
    result = new_state.pop
    discard new_state.empty
    new_state.tokens = tokens
    return result

proc barkStartCompile(s: var State): Option[int] =
  if not s.compile:
    s.compile = true
    return none(int)
  else:
    s.error = "error"
    echo "Error: compile mode already started."
    discard

var dictionary = {"+":barkMakeCompatible(barkPlus),
                  "-":barkMakeCompatible(barkMinus),
                  "print":barkMakeCompatible(barkPrint),
                  "branch":barkMakeCompatible(barkBranch),
                  "branch?":barkMakeCompatible(barkZeroBranch),
                  "halt":barkMakeCompatible(barkHalt),
                  ":":barkMakeCompatible(barkStartCompile)}.toTable

var immediate_words = @[":", ";"]

proc barkEndCompile(s: var State): Option[int] =
  if s.compile and len(s.new_word) != 0:
    dictionary[s.new_word[0]] = barkMakeWord(s.new_word[1..^1])
    s.compile = false
    s.new_word = @[]
    return none(int)
  elif s.compile and len(s.new_word) == 0:
    s.compile = false
    return none(int)
  else:
    s.error = "error"
    echo "Error: compile mode not started."

dictionary[";"] = barkMakeCompatible(barkEndCompile) # this word is only special because it alters the dictionary

proc barkNextTokenEffect(s: var State) =
  if s.token_idx >= s.tokens.len():
    return
  if (not s.compile) or (immediate_words.find(s.tokens[s.token_idx]) != -1):
    if dictionary.hasKey(s.tokens[s.token_idx]):
      discard dictionary[s.tokens[s.token_idx]](s)
    else:
      try:
        s.error = "ok"
        discard s.put(parseInt(s.tokens[s.token_idx]))
      except ValueError:
        echo "Error: undefined word."
        discard
  else:
    s.new_word.add(s.tokens[s.token_idx])
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
  --help           Show this text.
  -v --version     Show version.
"""
  let args = docopt(doc, version = "bark 0.1.0")


  var state: State
  discard state.empty
  var input_string: string
  stdout.write "bark 0.1.0 by Luka Hadzi-Djokic"
  while true:
    stdout.write "\n> "
    var stdin_stream = newFileStream(stdin)
    input_string = stdin_stream.readLine
    state.tokens = @[]
    state.token_idx = 0
    for token in input_string.splitWhitespace():
      state.tokens.add(token)
    barkRunProgram(state)
    stdout.write $state

