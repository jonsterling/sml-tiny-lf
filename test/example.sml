structure Example =
struct

  structure Sg = 
  struct
    datatype constant = 
       NAT  | ZE  | SU 
     | EXP | LAM  | AP
     | DIM | I0 | I1 | DIMABS | DIMAP

    val toString = 
      fn NAT => "nat"
       | EXP => "exp"
       | ZE => "ze"
       | SU => "su"
       | LAM => "lam"
       | AP => "ap"
       | DIM => "dim"
       | I0 => "0"
       | I1 => "1"
       | DIMABS => "dimabs"
       | DIMAP => "face"

    val eq : constant * constant -> bool = op=
    fun compare (o1, o2) = String.compare (toString o1, toString o2)
  end

  structure Sym = LfSymbolWithConstants (Sg)
  structure Syn = LfSyntax (Sym)
  structure TinyLf = LfTyping (Syn)

  open TinyLf Sym
  infix `@ \\ --> ==>

  val Nat = C Sg.NAT `@ []
  val Exp = C Sg.EXP `@ []
  val Dim = C Sg.DIM `@ []
  val I0 = C Sg.I0 `@ []
  val I1 = C Sg.I1 `@ []
  val Ze = C Sg.ZE `@ []
  fun Su e = C Sg.SU `@ [[] \\ e]
  fun Lam (x, e) = C Sg.LAM `@ [[x] \\ e]

  val mySig : ctx = 
    [(C Sg.NAT, [] ==> TYPE),
     (C Sg.EXP, [] ==> TYPE),
     (C Sg.ZE, [] ==> `Nat),
     (C Sg.SU, [[] ==> `Nat] ==> `Nat),
     (C Sg.LAM, [[[] ==> `Exp] ==> `Exp] ==> `Exp)]

  fun test () = 
    let
      val three = Su (Su (Su Ze))
      val threeTy = inf mySig three
      val welp = ctx [] mySig
      val x = Sym.named "x"
      val _ = print (Print.rtm (Lam (x, x `@ [])) ^ "\n")
      val _ = print (Print.ctx mySig ^ "\n")
      val _ = print (Print.rtm three ^ " : " ^ Print.rclass threeTy ^ "\n")
    in
      ()
    end

  val _ = LfExn.debug test

end