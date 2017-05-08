structure Example =
struct

  structure Sg = 
  struct
    datatype constant = 
       ZE  | SU 
     | EXP | INH | LAM  | AP
     | NAT | ARR

    val toString = 
      fn EXP => "exp"
       | INH => "inh"
       | NAT => "nat"
       | ARR => "arr"
       | ZE => "ze"
       | SU => "su"
       | LAM => "lam"
       | AP => "ap"
  

    val eq : constant * constant -> bool = op=
    fun compare (o1, o2) = String.compare (toString o1, toString o2)
  end

  structure Sym = LfSymbolWithConstants (Sg)
  structure Syn = LfSyntax (Sym)
  structure TinyLf = LfTyping (Syn)

  open TinyLf Sym
  infix 3 `@
  infixr 2 \ \\ --> ==>

  val Exp = C Sg.EXP `@ []

  val Ze = C Sg.ZE `@ []
  val Nat = C Sg.NAT `@ []
  fun Su e = C Sg.SU `@ [[] \\ e]
  fun Lam (x, e) = C Sg.LAM `@ [[x] \\ e]
  fun Inh e = C Sg.INH `@ [[] \\ e]
  fun Arr (s, t) = C Sg.ARR `@ [[] \\ s, [] \\ t]

  val mySig : ctx = 
    [(C Sg.EXP, [] ==> TYPE),
     (C Sg.INH, [[] ==> `Exp] ==> TYPE),
     (C Sg.NAT, [] ==> `Exp),
     (C Sg.ZE, [] ==> `Exp),
     (C Sg.SU, [[] ==> `Exp] ==> `Exp),
     (C Sg.LAM, [[[] ==> `Exp] ==> `Exp] ==> `Exp)]

  structure Rules = 
  struct
    structure Lf = TinyLf
    datatype rule = NAT_Z | NAT_S | ARR_I | HYP of Lf.var
    val printRule = 
      fn NAT_Z => "nat/z"
       | NAT_S => "nat/s"
       | ARR_I => "arr/i"
       | HYP x => "hyp[" ^ Lf.Sym.toString x ^ "]"

    type goal = (Lf.var * Lf.class, Lf.rclass) Lf.bind
    type state = (Lf.var * goal, Lf.ntm) Lf.bind 
    type names = unit -> Lf.var


   fun prependHyps (H : ctx) (cl : class) : goal = 
      let
        val Psi \ rcl = Unbind.class cl
      in
        H @ Psi \ rcl
      end

    fun Hyp (z  : var) (H \ rcl) = 
      let
        val hypcl = Inf.var H z
        val Psi \ rcl' = Unbind.class hypcl
        val Psi' = map (fn (x, cl : class) => (x, prependHyps H cl)) Psi
        val true = Eq.rclass (rcl, rcl')
      in
        Psi' \ map #1 H \\ z `@ map (fn (x, H \ rcl) => eta (x, H --> rcl)) Psi'
      end

    fun NatZ (H \ `inh) =
      let
        val C Sg.INH `@ [[] \ C Sg.NAT `@ []] = Unbind.rtm inh
        val xs = map #1 (H : ctx)
      in
        [] \ xs \\ Ze
      end

    fun NatS (H \ `inh) =
      let
        val C Sg.INH `@ [[] \ C Sg.NAT `@ []] = Unbind.rtm inh
        val X = Sym.named "X"
        val Psi = [(X, H \ `(Inh Nat))]
      in
        Psi \ map #1 H \\ Su (X `@ map eta H)
      end

    fun ArrI x (H \ `inh) =
      let
        val C Sg.INH `@ [[] \ arr] = Unbind.rtm inh
        val C Sg.ARR `@ [[] \ tyA, [] \ tyB] = Unbind.rtm arr

        val X = Sym.named "X"

        val Hx = H @ [(x, [] ==> `(Inh tyA))]
        val Psi = [(X, Hx \ `(Inh tyB))]
      in
        Psi \ map #1 H \\ Lam (x, X `@ map eta Hx)
      end

    fun rule fresh = 
      fn NAT_Z => NatZ 
       | NAT_S => NatS
       | ARR_I => ArrI (fresh ())
       | HYP x => Hyp x
  end

  structure Refiner = LfRefiner (Rules)

  fun test () = 
    let
      open Refiner Rules
      val sequence = List.foldr SEQ (EACH [])
      val >>> = BIND
      infix >>>

      val x = Sym.named "xwelp"
      val script =
        [x] >>>
        sequence
          [DEBUG "start",
           ALL (RULE ARR_I),
           DEBUG "arr/i",
           ALL (RULE NAT_S),
           DEBUG "nat/s",
           ALL (RULE (HYP x)),
           DEBUG "hyp"]

      val goal = [] \ `(Inh (Arr (Nat, Nat)))
      val machine = init (MT script) goal
    in
      eval machine
    end

  fun debug x = 
    LfExn.debug x 
    handle Refiner.Exn.Refine err => 
      (print ("\n\n" ^ Refiner.Exn.description err ^ "\n\n");
       raise Refiner.Exn.Refine err)

  val _ = debug test

end