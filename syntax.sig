signature LF_SYNTAX = 
sig
  structure Sym : SYMBOL
  type var = Sym.symbol
  type 'a env = 'a Sym.Env.dict

  type ntm (* normal terms *)
  type spine = ntm list
  type class (* general classifiers *)
  type ctx = (var * class) list

  datatype rclass = ` of rtm  | TYPE (* atomic classifiers *)
  and rtm = `@ of var * ntm list (* atomic terms *)

  datatype ('a, 'b) binder = \ of 'a list * 'b

  val \\ : var list * rtm -> ntm
  val --> : ctx * rclass -> class
  val ==> : class list * rclass -> class

  structure Unbind :
  sig
    val ntm : ntm -> (var, rtm) binder
    val class : class -> (var * class, rclass) binder
  end

  (* alpha equivalence *)
  structure Eq :
  sig
    val var : var * var -> bool
    val rclass : rclass * rclass -> bool
    val class : class * class -> bool
    val rtm : rtm * rtm -> bool
    val ntm : ntm * ntm -> bool
    val spine : spine * spine -> bool 
    val ctx : ctx * ctx -> bool
  end

  (* capture-avoiding renaming *)
  structure Ren :
  sig
    type ren = var env
    val rclass : ren -> rclass -> rclass
    val class : ren -> class -> class
    val rtm : ren -> rtm -> rtm 
    val ntm : ren -> ntm -> ntm
    val spine : ren -> spine -> spine 
    val ctx : ren -> ctx -> ren * ctx

    val rebindCtx : var list -> ctx -> ren * ctx
  end

  (* capture-avoiding substitution *)
  structure SubstN : 
  sig
    val rclass : ntm env -> rclass -> rclass
    val class : ntm env -> class -> class
    val rtm : ntm env -> rtm -> rtm
    val ntm : ntm env -> ntm -> ntm
    val spine : ntm env -> spine -> spine 
    val ctx : ntm env -> ctx -> ctx

    val zipSpine : var list * spine -> ntm env
  end

  structure SubstRcl :
  sig
    type subst = (var, rclass) binder env
    val rclass : subst -> rclass -> rclass
    val class : subst -> class -> class
    val rtm : subst -> rtm -> rtm
    val ntm : subst -> ntm -> ntm
    val spine : subst -> spine -> spine 
    val ctx : subst -> ctx -> ctx
  end

  structure Print : 
  sig
    val var : var -> string
    val rclass : rclass -> string
    val class : class -> string
    val rtm : rtm -> string
    val ntm : ntm -> string 
    val spine : spine -> string
    val ctx : ctx -> string
  end
end