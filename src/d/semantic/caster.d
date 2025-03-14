module d.semantic.caster;

import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;

import source.exception;

Expression buildImplicitCast(
	SemanticPass pass,
	Location location,
	Type to,
	Expression e,
) {
	return buildCast!false(pass, location, to, e);
}

Expression buildExplicitCast(
	SemanticPass pass,
	Location location,
	Type to,
	Expression e,
) {
	return buildCast!true(pass, location, to, e);
}

CastKind implicitCastFrom(SemanticPass pass, Type from, Type to) {
	return ImplicitCaster(pass, to).castFrom(from);
}

CastKind explicitCastFrom(SemanticPass pass, Type from, Type to) {
	return ExplicitCaster(pass, to).castFrom(from);
}

private:

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

Expression buildCast(bool isExplicit)(
	SemanticPass pass,
	Location location,
	Type to,
	Expression e,
) in {
	assert(e, "Expression must not be null");
} do {
	// If the expression is polysemous, we try the several meaning and
	// exclude the ones that make no sense.
	if (auto asPolysemous = cast(PolysemousExpression) e) {
		Expression casted;
		foreach(candidate; asPolysemous.expressions) {
			candidate = buildCast!isExplicit(pass, location, to, candidate);
			
			import d.ir.error;
			if (cast(ErrorExpression) candidate) {
				continue;
			}
			
			if (casted) {
				return new CompileError(location, "Ambiguous").expression;
			}
			
			casted = candidate;
		}
		
		if (casted) {
			return casted;
		}
		
		import d.ir.error;
		return new CompileError(location, "No match found").expression;
	}
	
	// When casting an array literal, we try to push down the
	// cast to each element of the literal.
	if (auto al = cast(ArrayLiteral) e) {
		switch (to.kind) with(TypeKind) {
			case Array:
				if (al.values.length != to.size) {
					import d.ir.error;
					return new CompileError(
						al.location,
						"Incorrect element count",
					).expression;
				}
				
				goto case;
				
			case Slice:
				import std.algorithm, std.array;
				auto et = to.element;
				auto values = al.values
					.map!(v => buildCast!isExplicit(pass, location, et, v))
					.array();
				return build!ArrayLiteral(e.location, to, values);
			
			default:
				break;
		}
	}
	
	auto kind = Caster!(isExplicit, delegate CastKind(c, t) {
		alias T = typeof(t);
		static if (is(T : Aggregate)) {
			static struct AliasThisResult {
				Expression expr;
				CastKind level;
			}
			
			auto level = CastKind.Invalid;
			enum InvalidResult = AliasThisResult(null, CastKind.Invalid);
			
			import d.semantic.aliasthis;
			import std.algorithm;
			auto results = AliasThisResolver!((identified) {
				alias T = typeof(identified);
				static if (is(T : Expression)) {
					auto oldE = e;
					scope(exit) e = oldE;
					e = identified;
					
					auto cLevel = c.castFrom(identified.type, to);
					if (cLevel == CastKind.Invalid || cLevel < level) {
						return InvalidResult;
					}
					
					level = cLevel;
					return AliasThisResult(identified, cLevel);
				} else {
					return InvalidResult;
				}
			})(pass).resolve(e, t).filter!(r => r.level == level);
			
			if (level == CastKind.Invalid) {
				return CastKind.Invalid;
			}
			
			Expression candidate;
			foreach(r; results) {
				if (candidate !is null) {
					return CastKind.Invalid;
				}
				
				candidate = r.expr;
			}
			
			assert(candidate, "if no candidate are found, level should be Invalid");
			
			e = candidate;
			return level;
		} else static if (is(T : BuiltinType)) {
			auto to = c.to;
			if (to.kind != TypeKind.Builtin || !canConvertToIntegral(to.builtin)) {
				return CastKind.Invalid;
			}
			
			assert(getSize(to.builtin) < getSize(t));
			
			import d.semantic.vrp;
			return ValueRangePropagator!uint(pass).canFit(e, to)
				? CastKind.Trunc
				: CastKind.Invalid;
		} else {
			return CastKind.Invalid;
		}
	})(pass, to).castFrom(e.type);
	
	switch(kind) with(CastKind) {
		case Exact:
			// FIXME: Because we don't cast type qualifier the proper
			// way, we need to make sure they match.
			e.type = e.type.qualify(to.qualifier);
			return e;
		
		default:
			return new CastExpression(location, kind, to, e);
		
		case Invalid:
			if (to.kind == TypeKind.Error) {
				return to.error.expression;
			}
			
			import d.ir.error;
			if (auto ee = cast(ErrorExpression) e) {
				return ee;
			}
			
			return new CompileError(
				location,
				"Can't cast " ~ e.type.toString(pass.context)
					~ " to " ~ to.toString(pass.context),
			).expression;
	}
}

alias ExplicitCaster = Caster!true;
alias ImplicitCaster = Caster!false;

struct Caster(bool isExplicit, alias bailoutOverride = null) {
	// XXX: Used only to get to super class, should probably go away.
	private SemanticPass pass;
	alias pass this;
	
	Type to;
	
	this(SemanticPass pass, Type to) {
		this.pass = pass;
		this.to = to;
	}
	
	enum hasBailoutOverride = !is(typeof(bailoutOverride) : typeof(null));
	
	CastKind bailout(T)(T t) {
		static if (hasBailoutOverride) {
			return bailoutOverride(this, t);
		} else {
			return CastKind.Invalid;
		}
	}
	
	CastKind bailoutDefault(T)(T t) {
		return CastKind.Invalid;
	}
	
	CastKind castFrom(ParamType from, ParamType to) {
		if (from.isRef != to.isRef) {
			return CastKind.Invalid;
		}
		
		auto k = castFrom(from.getType(), to.getType());
		if (from.isRef && k < CastKind.Qual) {
			return CastKind.Invalid;
		}
		
		return k;
	}
	
	// FIXME: handle qualifiers.
	CastKind castFrom(Type from) {
		from = from.getCanonical();
		to = to.getCanonical();
		
		if (from == to) {
			return CastKind.Exact;
		}
		
		return from.accept(this);
	}
	
	CastKind castFrom(Type from, Type to) {
		this.to = to;
		return castFrom(from);
	}
	
	CastKind visit(BuiltinType t) {
		if (isExplicit && to.kind == TypeKind.Enum) {
			to = to.getCanonicalAndPeelEnum();
			auto k = visit(t);
			return (k == CastKind.Exact)
				? CastKind.Bit
				: k;
		}
		
		// Can cast typeof(null) to class, pointer and function.
		if (t == BuiltinType.Null && to.hasPointerABI()) {
			return CastKind.Bit;
		}
		
		// Can explicitely cast integral to pointer.
		if (isExplicit && (to.kind == TypeKind.Pointer && canConvertToIntegral(t))) {
			return CastKind.IntToPtr;
		}
		
		if (to.kind != TypeKind.Builtin) {
			return CastKind.Invalid;
		}
		
		auto bt = to.builtin;
		if (t == bt) {
			return CastKind.Exact;
		}
		
		final switch(t) with(BuiltinType) {
			case None :
			case Void :
				return CastKind.Invalid;
			
			case Bool :
				if (isIntegral(bt)) {
					return CastKind.UPad;
				}
				
				return CastKind.Invalid;
			
			case Char :
				t = integralOfChar(t);
				goto case Ubyte;
			
			case Wchar :
				t = integralOfChar(t);
				goto case Ushort;
			
			case Dchar :
				t = integralOfChar(t);
				goto case Uint;
			
			case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent, Ucent :
				if (isExplicit && bt == Bool) {
					return CastKind.IntToBool;
				}
				
				if (!isIntegral(bt)) {
					return CastKind.Invalid;
				}
				
				auto ut = unsigned(t);
				bt = unsigned(bt);
				if (ut == bt) {
					return CastKind.Bit;
				} else if (ut < bt) {
					return isSigned(t)
						? CastKind.SPad
						: CastKind.UPad;
				} else static if (isExplicit) {
					return CastKind.Trunc;
				} else {
					return bailout(t);
				}
			
			case Float, Double, Real :
				assert(0, "Floating point casts are not implemented");
			
			case Null :
				return CastKind.Invalid;
		}
	}
	
	CastKind visitPointerOf(Type t) {
		// You can explicitely cast pointer to class, function.
		if (isExplicit && to.kind != TypeKind.Pointer && to.hasPointerABI()) {
			return CastKind.Bit;
		}
		
		// It is also possible to cast to integral explicitely.
		if (isExplicit && to.kind == TypeKind.Builtin) {
			if (canConvertToIntegral(to.builtin)) {
				return CastKind.PtrToInt;
			}
		}
		
		if (to.kind != TypeKind.Pointer) {
			return CastKind.Invalid;
		}
		
		auto e = to.element.getCanonical();
		
		// Cast to void* is kind of special.
		if (e.kind == TypeKind.Builtin && e.builtin == BuiltinType.Void) {
			return (isExplicit || canConvert(t.qualifier, e.qualifier))
				? CastKind.Bit
				: CastKind.Invalid;
		}
		
		auto subCast = castFrom(t, e);
		switch(subCast) with(CastKind) {
			case Qual:
				if (canConvert(t.qualifier, e.qualifier)) {
					return Qual;
				}
				
				goto default;
			
			case Exact:
				return Qual;
			
			static if (isExplicit) {
				default:
					return Bit;
			} else {
				case Bit :
					if (canConvert(t.qualifier, e.qualifier)) {
						return subCast;
					}
					
					goto default;
				
				default:
					return Invalid;
			}
		}
	}
	
	CastKind visitSliceOf(Type t) {
		if (to.kind != TypeKind.Slice) {
			return CastKind.Invalid;
		}
		
		auto e = to.element.getCanonical();
		
		auto subCast = castFrom(t, e);
		switch(subCast) with(CastKind) {
			case Qual:
				if (canConvert(t.qualifier, e.qualifier)) {
					return Qual;
				}
				
				goto default;
			
			case Exact:
				return Qual;
			
			static if (isExplicit) {
				default:
					return Bit;
			} else {
				case Bit:
					if (canConvert(t.qualifier, e.qualifier)) {
						return subCast;
					}
					
					goto default;
				
				default:
					return Invalid;
			}
		}
	}
	
	CastKind visitArrayOf(uint size, Type t) {
		if (to.kind != TypeKind.Array) {
			return CastKind.Invalid;
		}
		
		if (size != to.size) {
			return CastKind.Invalid;
		}
		
		auto e = to.element.getCanonical();
		
		auto subCast = castFrom(t, e);
		switch(subCast) with(CastKind) {
			case Qual:
				if (canConvert(t.qualifier, e.qualifier)) {
					return Qual;
				}
				
				goto default;
			
			case Exact:
				return Exact;
			
			static if (isExplicit) {
				default:
					return Bit;
			} else {
				case Bit:
					if (canConvert(t.qualifier, e.qualifier)) {
						return subCast;
					}
					
					goto default;
				
				default:
					return Invalid;
			}
		}
	}
	
	CastKind visit(Struct s) {
		if (to.kind == TypeKind.Struct) {
			if (to.dstruct is s) {
				return CastKind.Exact;
			}
		}
		
		return bailout(s);
	}
	
	private auto castClass(Class from, Class to) {
		if (from is to) {
			return CastKind.Exact;
		}
		
		auto upcast = from;
		
		// Stop at object.
		while(upcast !is upcast.base) {
			// Automagically promote to base type.
			upcast = upcast.base;
			
			if (upcast is to) {
				return CastKind.Bit;
			}
		}
		
		static if (isExplicit) {
			auto downcast = to;
			
			// Stop at object.
			while(downcast !is downcast.base) {
				// Automagically promote to base type.
				downcast = downcast.base;
				
				if (downcast is from) {
					return CastKind.Down;
				}
			}
		}
		
		return CastKind.Invalid;
	}
	
	CastKind visit(Class c) {
		if (isExplicit && to.kind == TypeKind.Pointer) {
			auto et = to.element.getCanonical();
			if (et.kind == TypeKind.Builtin &&
				et.builtin == BuiltinType.Void) {
				return CastKind.Bit;
			}
		}
		
		if (to.kind == TypeKind.Class) {
			scheduler.require(c, Step.Signed);
			auto kind = castClass(c, to.dclass);
			if (kind > CastKind.Invalid) {
				return kind;
			}
		}
		
		return bailout(c);
	}
	
	CastKind visit(Enum e) {
		if (to.kind == TypeKind.Enum) {
			if (e is to.denum) {
				return CastKind.Exact;
			}
		}
		
		// Automagically promote to base type.
		return castFrom(e.type);
	}
	
	CastKind visit(TypeAlias a) {
		return castFrom(a.type);
	}
	
	CastKind visit(Interface i) {
		return CastKind.Invalid;
	}
	
	CastKind visit(Union u) {
		return (to.kind == TypeKind.Union && to.dunion is u)
			? CastKind.Exact
			: CastKind.Invalid;
	}
	
	CastKind visit(Function f) {
		assert(0, "Cast to context type do not make any sense.");
	}
	
	CastKind visit(Type[] seq) {
		assert(0, "Cast to sequence type do not make any sense.");
	}
	
	CastKind visit(FunctionType f) {
		if (to.kind == TypeKind.Pointer && f.contexts.length == 0) {
			auto e = to.element.getCanonical();
			static if (isExplicit) {
				return CastKind.Bit;
			} else if (e.kind == TypeKind.Builtin && e.builtin == BuiltinType.Void) {
				// FIXME: qualifier.
				return CastKind.Bit;
			} else {
				return CastKind.Invalid;
			}
		}
		
		if (to.kind != TypeKind.Function) {
			return CastKind.Invalid;
		}
		
		auto tf = to.asFunctionType();
		
		if (f.contexts.length != tf.contexts.length) {
			return CastKind.Invalid;
		}
		
		enum onFail = isExplicit ? CastKind.Bit : CastKind.Invalid;
		
		if (f.parameters.length != tf.parameters.length) {
			return onFail;
		}
		
		if (f.isVariadic != tf.isVariadic) {
			return onFail;
		}
		
		if (f.linkage != tf.linkage) {
			return onFail;
		}
		
		auto k = castFrom(f.returnType, tf.returnType);
		if (k < CastKind.Bit) {
			return onFail;
		}
		
		import std.range;
		foreach(fromc, toc; lockstep(f.contexts, tf.contexts)) {
			// ref context decay to void*
			if (fromc.isRef && !toc.isRef &&
				toc.kind == TypeKind.Pointer) {
				
				auto e = toc.getType().element;
				if (e.kind == TypeKind.Builtin &&
					e.builtin == BuiltinType.Void) {
				
					k = CastKind.Bit;
					continue;
				}
			}
			
			// Contexts are covariant.
			auto kc = castFrom(fromc, toc);
			if (kc < CastKind.Bit) {
				return onFail;
			}
			
			import std.algorithm;
			k = min(k, kc);
		}
		
		foreach(fromp, top; lockstep(f.parameters, tf.parameters)) {
			// Parameters are contrevariant.
			auto kp = castFrom(top, fromp);
			if (kp < CastKind.Bit) {
				return onFail;
			}
			
			import std.algorithm;
			k = min(k, kp);
		}
		
		return (k < CastKind.Exact) ? CastKind.Bit : CastKind.Exact;
	}
	
	CastKind visit(Pattern p) {
		assert(0, "Pattern cannot be casted.");
	}
	
	import d.ir.error;
	CastKind visit(CompileError e) {
		return CastKind.Invalid;
	}
}
