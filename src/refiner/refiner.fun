functor LfRefiner (R : LF_RULES) : LF_REFINER = 
struct
  structure Rules = R
  open R

  structure LfPrint = LfSyntaxPrint (Lf)

  fun @@ (f, x) = f x
  infix @@

  exception todo fun ?e = raise e
  type name_block = Lf.var list
  type names = name_block list

  fun mapSnd f (x, y) =
    (x, f y)

  fun popName (names : names) : Lf.var * names = 
    case names of 
       [] => (Lf.Sym.new (), [])
     | [] :: names => mapSnd (fn names' => [] :: names') (popName names)
     | (x :: xs) :: names => (x, xs :: names)

  datatype tactic =
     RULE of rule
   | MT of multitactic

  and multitactic = 
     ALL of tactic
   | EACH of tactic list
   | DEBUG of string
   | BIND of Rules.Lf.var list * multitactic
   | SEQ of multitactic * multitactic
   | ORELSE of multitactic * multitactic

  (* The refinement machine has five instructions:
       1. [MTAC mtac] means "run [mtac] on returned proof state"
       2. [AWAIT (x, mtac, st)] means "wait for [x] to emit a proof state, and merge it with [st], and continue executing with [mtac]"
       3. [PREPEND Psi] means "prepend the subgoals Psi onto the returned proof state"
       4. [POP_NAMES] pops a user-supplied name block off the name supply stack
       5. [HANDLE cfg] means "in case of an error, restore the machine state [cfg]"
   *)
  datatype instr =
     MTAC of multitactic
   | AWAIT of Lf.var * multitactic * state
   | PREPEND of (Lf.var * goal) list
   | POP_NAMES
   | HANDLE of machine_multi

  withtype stack = instr list

  and machine_focus = {tactic: tactic, goal: goal, stack: stack, names: name_block list}
  and machine_multi = {multitactic: multitactic, state: state, stack: stack, names: name_block list}
  and machine_retn = {state: state, stack: stack, names: name_block list}
  and machine_throw = {exn: exn, goal: goal, trace: stack, stack: stack}

  (* The refinement machine has four execution states:
       1. Executing a tactic on a focused goal
       2. Executing a multitactic on a proof state
       3. Returning a proof state
       4. Throwing an error
   *)
  datatype machine = 
     FOCUS of machine_focus
   | MULTI of machine_multi
   | RETN of machine_retn
   | THROW of machine_throw

  datatype 'a step = 
     STEP of 'a
   | FINAL of state

  fun init tac goal = 
    FOCUS
      {tactic = tac,
       goal = goal,
       stack = [],
       names = []}

  open Lf infix \ \\ `@ ==> -->

  structure Goal :
  sig
    val class : goal -> class
    val ctx : (var * goal) list -> ctx
    val ren : var Sym.Env.dict -> goal -> goal
    val subst : ntm Sym.Env.dict -> goal -> goal
  end = 
  struct
    fun class (Psi \ rcl) = 
      Psi --> rcl

    val ctx : (var * goal) list -> ctx = 
      List.map (mapSnd class)

    fun subst rho (Psi \ rcl) = 
      let
        val cl = SubstN.class rho (Psi --> rcl)
        val Psi' \ rcl' = Unbind.class cl
        val (rho', Psi'') = Ren.rebindCtx (List.map #1 Psi) Psi'
      in
        Psi'' \ Ren.rclass rho' rcl'
      end

    fun ren rho (Psi \ rcl) = 
      let
        val cl = Ren.class rho (Psi --> rcl)
        val Psi' \ rcl' = Unbind.class cl
        val (rho', Psi'') = Ren.rebindCtx (List.map #1 Psi) Psi'
      in
        Psi'' \ Ren.rclass rho' rcl'
      end
  end

  fun substState rho (Psi \ evd : state) = 
    let
      val rho' = List.foldr (fn ((x, _), rho) => Sym.Env.remove rho x) rho Psi
      val Psi' = map (mapSnd (Goal.subst rho')) Psi
      val evd' = SubstN.ntm rho' evd
    in
      Psi' \ evd'
    end

  fun renState rho (Psi \ evd) = 
    let
      val Psi' = map (mapSnd (Goal.ren rho)) Psi
    in
      Psi' \ Ren.ntm rho evd
    end

  structure PP = PrettyPrint
  structure UP = Unparse  

  structure Pretty = 
  struct

    val unparse = UP.parens o UP.done 

    fun sep d xs : string = 
      case xs of 
         [] => ""
       | [x] => x
       | x :: xs => x ^ d ^ sep d xs

    val commaSep = sep ", "
    fun squares x = "[" ^ x ^ "]"
    fun quotes x = "\"" ^ x ^ "\""

    val var = Sym.toString
    val vars = commaSep o List.map var
    val nameBlocks = commaSep o List.map (squares o vars)

    fun tactic tac : string UP.part = 
      case tac of 
         RULE rl => UP.atom @@ printRule rl
       | MT mtac => multitactic mtac

    and multitactic mtac = 
      case mtac of 
         ALL tac => tactic tac
       | EACH tacs => UP.atom o squares o commaSep @@ List.map (unparse o tactic) tacs
       | DEBUG msg => UP.adj (UP.atom "debug", UP.atom @@ quotes msg)
       | SEQ (mtac1, mtac2) => UP.infix' (UP.Right, 0, ";") (multitactic mtac1, multitactic mtac2)
       | ORELSE (mtac1, mtac2) => UP.infix' (UP.Non, 5, "|") (multitactic mtac1, multitactic mtac2)
       | BIND (xs, mtac) => UP.infix' (UP.Left, 10, "<-") (UP.atom @@ vars xs, multitactic mtac)

    val instr : instr -> PP.doc = 
      fn MTAC mtac =>
         PP.concat 
           [PP.text "{", 
            PP.text o unparse @@ multitactic mtac,
            PP.text "}"]
       | AWAIT (x, mtac, st) =>
         PP.concat 
           [PP.text "await ", 
            PP.text @@ Sym.toString x,
            PP.text " with ",
            PP.text o unparse @@ multitactic mtac]
       | POP_NAMES => PP.text "pop-names"
       | HANDLE _ => PP.text "handler"
       | _ => PP.text "TODO"

    fun intercalate d xs = 
      case xs of 
         [] => []
       | [x] => [x]
       | x::xs => x :: d :: intercalate d xs

    fun stack stk = 
      PP.group o PP.concat @@
        intercalate (PP.newline) (List.map (fn x => PP.concat [PP.text "* ", instr x]) stk)

    fun hyp (x, cl) = 
      PP.concat
        [PP.text @@ Sym.toString x,
         PP.text " : ",
         PP.text @@ LfPrint.class cl]

    fun hyps Psi =
      PP.group o PP.concat @@
        intercalate (PP.newline) (List.map hyp Psi)

    fun goal (x, Psi \ rcl : goal) : PP.doc =
      PP.concat 
        [PP.text "Goal ", PP.text @@ Sym.toString x,
         PP.newline,
         PP.rule #"-",
         PP.group @@ hyps Psi,
         PP.newline,
         PP.text ">> ",
         PP.text @@ LfPrint.rclass rcl]

    fun goals gls =
      case gls of 
         [] => PP.text "[no subgoals]"
       | _ => PP.group o PP.concat @@ intercalate (PP.concat [PP.newline, PP.newline]) (List.map goal gls)

    fun state (Psi \ evd : state) = 
      PP.concat
        [PP.nest 2 @@ PP.concat [PP.newline, goals Psi],
         PP.newline,PP.newline,
         PP.rule #"-",
         PP.nest 2 @@ PP.concat [PP.newline, PP.text @@ LfPrint.ntm evd]]
  end

  structure Print = 
  struct
    val stack = PrettyPrint.toString 80 false o Pretty.stack
  end

  structure Exn = 
  struct
    type refine_error = exn * Lf.class * stack
    exception Refine of refine_error

    fun description (exn, goal, stack) = 
      "[ERROR] "
        ^ exnMessage exn
        ^ " when refining goal "
        ^ LfPrint.class goal
        ^ "\n\nStack trace:\n"
        ^ Print.stack (List.rev stack)
  end

  fun goalToState (goal : goal) : state  = 
    let
      val x = Sym.new ()
    in
      [(x, goal)] \ eta (x, Goal.class goal)
    end

  fun runRule {ruleName, goal, stack, names} = 
    let
      val namesRef = ref names
      fun fresh () =
        let
          val names = !namesRef
          val (x, names') = popName names
        in
          namesRef := names'; x
        end 

      val state = rule fresh ruleName goal
    in
      RETN {state = state, stack = stack, names = !namesRef}
    end
    handle exn =>
      THROW
        {exn = exn,
         goal = goal,
         trace = [],
         stack = stack}

  fun stepFocus {tactic, goal, stack, names} : machine step = 
    case tactic of 
       RULE rl => 
         STEP o runRule @@ 
           {ruleName = rl,
            goal = goal,
            stack = stack,
            names = names}

     | MT mtac =>
         STEP o RETN @@
           {state = goalToState goal,
            stack = MTAC mtac :: stack,
            names = names}

  fun stepRetn {state as Psi \ evd, stack, names} : machine step = 
    case stack of 
       MTAC mtac :: stk =>
         STEP o MULTI @@
           {multitactic = mtac,
            state = state,
            stack = stk,
            names = names}

     | AWAIT (x, mtac, state) :: stk =>
       let
         val rhox = Sym.Env.singleton x evd
       in
         STEP o MULTI @@
           {multitactic = mtac,
            state = substState rhox state,
            stack = PREPEND Psi :: stk,
            names = names}
       end

     | PREPEND Psi' :: stk =>
         STEP o RETN @@
           {state = Psi' @ Psi \ evd,
            stack = stk,
            names = names}

     | HANDLE _ :: stk => 
         STEP o RETN @@
           {state = state,
            stack = stk,
            names = names}

     | POP_NAMES :: stk => 
         STEP o RETN @@ 
           {state = state,
            stack = stk,
            names = List.tl names}

     | [] => FINAL state

  fun stepThrow {exn, goal, trace, stack} : machine step =
    case stack of 
       [] => raise Exn.Refine (exn, Goal.class goal, trace)
     | HANDLE multi :: stk => STEP @@ MULTI multi
     | instr :: stk =>
         STEP o THROW @@
           {exn = exn,
            goal = goal,
            trace = instr :: trace,
            stack = stk}

  fun debugDoc msg {state, stack, names} : PP.doc = 
    PP.concat @@
      [PP.newline, PP.newline, PP.newline,
       PP.text ("[DEBUG] " ^ msg),
       PP.newline, PP.rule #"=", PP.newline,
       PP.text "Proof state:",
       PP.newline,
       PP.rule #"-",
       PP.nest 2 @@ Pretty.state state,
       PP.newline, PP.newline, PP.newline]
      @ (if List.length stack = 0 then [] else 
           [PP.text "Remaining tasks:",
            PP.newline,
            PP.rule #"-",
            PP.nest 2 o PP.concat @@ [PP.newline, Pretty.stack stack],
            PP.newline, PP.newline, PP.newline])
      @ (if List.length names = 0 then [] else
           [PP.text "Name blocks:",
            PP.newline,
            PP.rule #"-",
            PP.nest 2 o PP.concat @@ [PP.newline, PP.text @@ Pretty.nameBlocks names]])

    
  fun debugString msg =
    PrettyPrint.toString 80 false 
      o debugDoc msg

  fun stepMulti (multi as {multitactic, state as Psi \ evd, stack, names}) : machine step =
    case (Psi, multitactic) of 
       (_, DEBUG msg) =>
       let
         val retn = {state = state, stack = stack, names = names}
         val debugStr = debugString msg retn
       in 
         print debugStr;
         STEP @@ RETN retn
       end

     | (_, SEQ (mtac1, mtac2)) =>
       STEP o MULTI @@
         {multitactic = mtac1,
          state = state,
          stack = MTAC mtac2 :: stack,
          names = names}

     | (_, BIND (xs, mtac)) => 
        STEP o MULTI @@
          {multitactic = mtac,
           state = state,
           stack = POP_NAMES :: stack,
           names = xs :: names}

     | ([], _) =>
       STEP o RETN @@
         {state = state,
          stack = stack,
          names = names}

     | ((x, goal) :: Psi, ALL tac) =>
       STEP o FOCUS @@
         {tactic = tac,
          goal = goal,
          stack = AWAIT (x, ALL tac, Psi \ evd) :: stack, 
          names = names}

     | (_, EACH []) =>
       STEP o RETN @@
         {state = state,
          stack = stack,
          names = names}

     | ((x, goal) :: Psi, EACH (tac :: tacs)) =>
       STEP o FOCUS @@
         {tactic = tac,
          goal = goal,
          stack = AWAIT (x, EACH tacs, Psi \ evd) :: stack,
          names = names}

     | (_, ORELSE (mtac1, mtac2)) => 
       STEP o MULTI @@
         {multitactic = mtac1, 
          state = state,
          stack = HANDLE multi :: stack,
          names = names}

  val step : machine -> machine step = 
    fn FOCUS foc => stepFocus foc
     | MULTI multi => stepMulti multi
     | THROW throw => stepThrow throw
     | RETN retn => stepRetn retn

  fun eval m = 
    case step m of 
       STEP m => eval m
     | FINAL st => st
end