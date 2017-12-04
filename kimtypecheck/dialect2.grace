#pragma ExtendedLineups
//dialect "none"
//import "standardGrace" as sg
import "errormessages" as errormessages
import "ast" as ast
import "io" as io

inherit prelude.methods

//method methods {
//    prelude.clone(self)
//}

// Checker error

def CheckerFailure is public = prelude.Exception.refine "CheckerFailure"

type List = prelude.List

// Helper Map

class entryFrom (key') to(value') is confidential {
    def key is public = key'
    var value is public := value'
}

class aMutableMap {

    def entries = outer.list[]

    method isEmpty -> Boolean { size == 0 }

    method size -> Number { entries.size }

    method at (key) {
        atKey (key) do { value -> return value }

        prelude.NoSuchObject.raise "no key {key} in aMutableMap"
    }

    method at (key) put (value) -> Done {
        if (value.asString == "done") then {
            prelude.ProgrammingError.raise "mutableMap: attempting to put ‹done› at key {key}"
        }
        for(entries) do { entry ->
            if(entry.key == key) then {
                entry.value := value
                return done
            }
        }

        entries.push (entryFrom (key) to (value))
    }

    method keys -> List {
        def keys' = outer.list[]

        for (entries) do { entry ->
            keys'.push (entry.key)
        }

        return keys'
    }

    method values -> List {
        def values' = outer.list[]

        for (entries) do { entry ->
            values'.push (entry.value)
        }

        return values'
    }

    method containsKey (key) -> Boolean {
        atKey (key) do { _ -> return true }

        return false
    }

    method atKey(key) do(block) -> Done {
        atKey(key) do(block) else {}
        return
    }

    method atKey (key) do (block) else (block') {
        for (entries) do { entry ->
            if (entry.key == key) then {
                return block.apply (entry.value)
            }
        }

        return block'.apply
    }

    method asString -> String is override {
        if (isEmpty) then {
            return "\{\}"
        }

        var out := "\{"

        var once := false
        for (entries) do { entry ->
            if (once) then {
                out := "{out},"
            }
            out := "{out} {entry.key} => {entry.value}"
            once := true
        }

        return "{out} \}"
    }

}



// Rules

// The defined type rules.
def rules = outer.list[]

// The cached type assignments.
def cache = aMutableMap

// Add a new rule specified by block to set of rules.
method rule (block) -> Done {
    rules.push (block)
}

// Short fail-with-message

// Will be updated with each node examined
var currentLine := 0
method fail (message) {
    CheckerFailure.raise (message) with (object {
        def line is public = currentLine
        def linePos is public = 1
    })
}
method fail (message) at (p) {
    CheckerFailure.raise (message) with (p)
}
method fail (message) from (startPos) to (endPos) suggest (sugg) {
    def o = object {
        def line is public = currentLine
        def posStart is public = startPos
        def posEnd is public = endPos
        def suggestions is public = outer.list[sugg]
    }
    CheckerFailure.raise (message) with (o)
}
method fail (message) from (startPos) to (endPos) {
    def o = object {
        def line is public = currentLine
        def posStart is public = startPos
        def posEnd is public = endPos
        def suggestions is public = outer.list[]
    }
    CheckerFailure.raise (message) with (o)
}
method fail (msg) when (pat) {
    rule { x ->
        def mat = pat.match(x)
        if (mat && {mat.result}) then {
            fail (msg) at (x)
        } else {
            false
        }
    }
}
method createSuggestion {
    errormessages.suggestion.new
}
method when (pat) error (msg) {
    fail (msg) when (pat)
}

// Scope represents stack of scopes

class stackOfKind(kind : String) is confidential {
    def stack is public = outer.list[aMutableMap]

    // add <name,value> to current scope
    method at (name : String) put (value) -> Done {
        stack.last.at(name) put(value)
    }

    // Find name in stack of current scopes & return its value
    // If not there perform action in bl
    method find (name : String) butIfMissing (bl) {
        var i := stack.size
        while { i > 0 } do {
            stack.at (i).atKey (name) do { value ->
                return value
            }

            i := i - 1
        }

        return bl.apply
    }

}

// scope consists of stacks of scopes for each of variables, methods, & types
def scope is public = object {
    def variables is public = stackOfKind ("variable")
    def methods is public = stackOfKind ("method")
    def types is public = stackOfKind ("type")

    method size -> Number {
        variables.stack.size
    }

    method enter (bl) {
        variables.stack.push (aMutableMap)
        methods.stack.push (aMutableMap)
        types.stack.push (aMutableMap)

        def result = bl.apply

        variables.stack.pop
        methods.stack.pop
        types.stack.pop

        return result
    }

    method asString -> String is override {
        "scope<{size}>"
    }
}

method checkTypes (node) {
//    io.error.write "231: checking types of {node}"
    node.accept (astVisitor)
//    io.error.write "233: done checking types of {node}"
}

method typeOf (node) {
    checkTypes (node)
    cache.atKey (node) do { value -> return value }
    CheckerFailure.raise "cannot type non-expression {node}" with (node)
}

method runRules (node) {
    // apply all rules to node; returns the last SuccessfulMatch.
    // if there is no successful match, returns FailedMatch(node).
    cache.atKey (node) do { value -> return value }
    currentLine := node.line
    var result := false //prelude.FailedMatch.new(node)
    for (rules) do { each ->
        def matched = each.match (node)
        if (matched) then {
            result := matched.result
            io.error.write "252 found matching rule for {node} with result {result}"
            if (result.asString == "done") then {
                prelude.ProgrammingError.raise 
                   "each.match(node) has result 'done' when each == {each} and node = {node}"
            }
            io.error.write "257 ready to cache {node} with result {result}"
            cache.at (node) put (result)
//            io.error.write "257 cached {node} with result {result}"
        }
    }
    return result
}


// Type checker

// Checks the defined rules on the given AST.
method check (module) -> Done {
    // Runs the check on the module object.
    module.accept (astVisitor)
}

type AstNode = { kind -> String }

class aPatternMatchingNode (kind : String) -> prelude.Pattern {
    inherit outer.BasicPattern.new

    method match (obj : Object) → prelude.MatchResult | false {
        match (obj) 
          case { node : AstNode ->
            if (kind == node.kind) then {
                prelude.SuccessfulMatch.new (node, outer.emptySequence)
            } else {
                false
            }
          } case { _ -> false }
    }
}

class booleanPattern (predicate) → prelude.MatchResult | false {
    method match (obj) {
        if (predicate.apply (obj)) then { 
            prelude.SuccessfulMatch.new (obj, outer.emptySequence)
        } else {
            false
        }
    }
}

def If is public = aPatternMatchingNode "if"
def BlockLiteral is public = aPatternMatchingNode "block"
def MatchCase is public = aPatternMatchingNode "matchcase"
def TryCatch is public = aPatternMatchingNode "trycatch"
def Outer is public = aPatternMatchingNode "outer"
def MethodSignature is public = aPatternMatchingNode "methodtype"
def TypeLiteral is public = aPatternMatchingNode "typeliteral"
def TypeDeclaration is public = aPatternMatchingNode "typedec"
def TypeAnnotation is public = aPatternMatchingNode "dtype"
def Member is public = aPatternMatchingNode "member"
def Method is public = aPatternMatchingNode "method"
def Parameter is public = aPatternMatchingNode "parameter"
def Request is public = booleanPattern { x → x.isCall }
def Class is public = aPatternMatchingNode "class"
def ObjectLiteral is public = aPatternMatchingNode "object"
def ArrayLiteral is public = aPatternMatchingNode "array"
def Generic is public = aPatternMatchingNode "generic"
def Identifier is public = aPatternMatchingNode "identifier"
def OctetsLiteral is public = aPatternMatchingNode "octets"
def StringLiteral is public = aPatternMatchingNode "string"
def NumberLiteral is public = aPatternMatchingNode "num"
def Operator is public = aPatternMatchingNode "op"
def Bind is public = aPatternMatchingNode "bind"
def Def is public = aPatternMatchingNode "defdec"
def Var is public = aPatternMatchingNode "vardec"
def Import is public = aPatternMatchingNode "import"
def Dialect is public = aPatternMatchingNode "dialect"
def Return is public = aPatternMatchingNode "return"
def Inherit is public = aPatternMatchingNode "inherit"
def Module is public = aPatternMatchingNode "module"

// Special requests patterns.

class RequestOf (methodName: String) -> prelude.Pattern {

    inherit outer.BasicPattern.new

    method match(obj:Object) -> prelude.MatchResult | false {
        match(obj) 
            case { node: AstNode ->
                if (node.isCall && {node.canonicalName == methodName}) then {
                    prelude.SuccessfulMatch.new (node, makeBindings (node))
                } else {
                    false // prelude.Failedmatch.new (node)
                }
            } case { _ ->
                false //prelude.Failedmatch.new (obj)
            }
    }

    method makeBindings(node) { outer.list[] }
}

def WhileRequest is public = RequestOf "while(_)do(_)"
def ForRequest is public = RequestOf "for(_)do(_)"

method whileCond (node) {
    // answers the condition expression from node, which must be a
    // a callNode calling "while(_)do(_)"
    def sig = node.parts
    sig.first.args.first
}

method whileBody (node) {
    // answers the body expression from node, which must be a
    // a callNode calling "while(_)do(_)"
    def sig = node.parts
    sig.second.args.first
}

method forCollection (node) {
    // answers the collection expression from node, which must be a
    // a callNode calling "for(_)do(_)"
    def sig = node.parts
    sig.first.args.first
}

method forBody (node) {
    // answers the body expression from node, which must be a
    // a callNode calling "for(_)do(_)"
    def sig = node.parts
    sig.second.args.first
}

def astVisitor = object {
    inherit ast.baseVisitor

    method checkMatch (node) -> Boolean {
        runRules (node)
        return true
    }

    method visitIf (node) -> Boolean {
        checkMatch (node)
    }

    method visitBlock (node) -> Boolean {
        io.error.write "398: visiting block {node}"
        runRules (node)

        for (node.params) do { param ->
            runRules (parameterFromNode (param))
        }

        for (node.body) do { stmt ->
            stmt.accept (self)
        }

        return false
    }

    method visitMatchCase (node) -> Boolean {
        checkMatch (node)
    }

    method visitTryCatch (node) -> Boolean {
        checkMatch (node)
    }

    method visitMethodType (node) -> Boolean {
//        io.error.write "430: visiting method type {node}"

        runRules (node)

        node.parametersDo { param ->
            runRules (parameterFromNode(param))
        }

        return false
    }

    method visitType (node) -> Boolean {
//        io.error.write "430: visiting type {node}"
        checkMatch (node)
//        io.error.write "432: done visiting type {node}"
    }

    method visitMethod (node) -> Boolean {
        io.error.write "430: visiting method {node}"
        runRules (node)

        node.parametersDo { param ->
            runRules (parameterFromNode (param))
        }

        for (node.body) do { stmt ->
            stmt.accept (self)
        }

        return false
    }

    method visitCall (node) -> Boolean {
        runRules (node)

        node.receiver.accept (self)
        
        node.argumentsDo { arg ->
            arg.accept (self)
        }

        return false
    }

    method visitObject (node) -> Boolean {
        checkMatch (node)
    }
    
    method visitModule (node) → Boolean {  // added kim
//        io.error.write "visiting module {node}"
        checkMatch (node)
    }

    method visitArray (node) -> Boolean {
        checkMatch (node)
    }

    method visitMember (node) -> Boolean {
        checkMatch (node)
    }

    method visitGeneric (node) -> Boolean {
        checkMatch (node)
    }

    method visitIdentifier (node) -> Boolean {
        checkMatch (node)
    }

    method visitOctets (node) -> Boolean {
        checkMatch (node)
    }

    method visitString (node) -> Boolean {
        checkMatch (node)
    }

    method visitNum (node) -> Boolean {
        checkMatch (node)
    }

    method visitOp (node) -> Boolean {
        checkMatch (node)
    }

    method visitBind (node) -> Boolean {
        checkMatch (node)
    }

    method visitDefDec (node) -> Boolean {
        checkMatch (node)
    }

    method visitVarDec (node) -> Boolean {
//        io.error.write "visiting var dec {node}"
        checkMatch (node)
    }

    method visitImport (node) -> Boolean {
        checkMatch (node)
    }

    method visitReturn (node) -> Boolean {
        checkMatch (node)
    }

    method visitInherits (node) -> Boolean {
        checkMatch (node)
    }

    method visitDialect (node) -> Boolean {
        checkMatch (node)
    }

}

class parameterFromNode (node) -> Parameter is confidential {
    inherit ast.identifierNode.new (node.name, node.dtype)
    method kind { "parameter" }
}

