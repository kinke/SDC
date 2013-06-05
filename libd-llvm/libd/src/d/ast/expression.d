module d.ast.expression;

import d.ast.adt;
import d.ast.base;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

abstract class Expression : Node {
	Type type;
	
	this(Location location) {
		this(location, null);
	}
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
	
	@property
	bool isLvalue() const {
		return false;
	}
}

/**
 * Any expression that have a value known at compile time.
 */
abstract class CompileTimeExpression : Expression {
	this(Location location) {
		super(location);
	}
	
	this(Location location, Type type) {
		super(location, type);
	}
}

// All expressions are final.
final:

/**
 * An Error occured but an Expression is expected.
 * Useful for speculative compilation.
 */
class ErrorExpression : CompileTimeExpression {
	string message;
	
	this(Location location, string message) {
		super(location);
		
		this.message = message;
	}
}

/**
 * Expression that can in fact be several expressions.
 * A good example is IdentifierExpression that resolve as overloaded functions.
 */
class PolysemousExpression : Expression {
	Expression[] expressions;
	
	this(Location location, Expression[] expressions) {
		super(location);
		
		this.expressions = expressions;
	}
	
	invariant() {
		assert(expressions.length > 1);
	}
}

/**
 * Conditional expression of type ?:
 */
class ConditionalExpression : Expression {
	Expression condition;
	Expression ifTrue;
	Expression ifFalse;
	
	this(Location location, Expression condition, Expression ifTrue, Expression ifFalse) {
		super(location);
		
		this.condition = condition;
		this.ifTrue = ifTrue;
		this.ifFalse = ifFalse;
	}
}

/**
 * Binary Expressions.
 */
class BinaryExpression(string operator) : Expression {
	Expression lhs;
	Expression rhs;
	
	this(Location location, Expression lhs, Expression rhs) {
		super(location);
		
		this.lhs = lhs;
		this.rhs = rhs;
	}
}

// XXX: Remove ?
alias BinaryExpression!","  CommaExpression;

alias BinaryExpression!"="  AssignExpression;

alias BinaryExpression!"+"  AddExpression;
alias BinaryExpression!"-"  SubExpression;
alias BinaryExpression!"~"  ConcatExpression;
alias BinaryExpression!"*"  MulExpression;
alias BinaryExpression!"/"  DivExpression;
alias BinaryExpression!"%"  ModExpression;
alias BinaryExpression!"^^" PowExpression;

alias BinaryExpression!"+="  AddAssignExpression;
alias BinaryExpression!"-="  SubAssignExpression;
alias BinaryExpression!"~="  ConcatAssignExpression;
alias BinaryExpression!"*="  MulAssignExpression;
alias BinaryExpression!"/="  DivAssignExpression;
alias BinaryExpression!"%="  ModAssignExpression;
alias BinaryExpression!"^^=" PowAssignExpression;

alias BinaryExpression!"||"  LogicalOrExpression;
alias BinaryExpression!"&&"  LogicalAndExpression;

alias BinaryExpression!"||=" LogicalOrAssignExpression;
alias BinaryExpression!"&&=" LogicalAndAssignExpression;

alias BinaryExpression!"|"   BitwiseOrExpression;
alias BinaryExpression!"&"   BitwiseAndExpression;
alias BinaryExpression!"^"   BitwiseXorExpression;

alias BinaryExpression!"|="  BitwiseOrAssignExpression;
alias BinaryExpression!"&="  BitwiseAndAssignExpression;
alias BinaryExpression!"^="  BitwiseXorAssignExpression;

alias BinaryExpression!"=="  EqualityExpression;
alias BinaryExpression!"!="  NotEqualityExpression;

alias BinaryExpression!"is"  IdentityExpression;
alias BinaryExpression!"!is" NotIdentityExpression;

alias BinaryExpression!"in"  InExpression;
alias BinaryExpression!"!in" NotInExpression;

alias BinaryExpression!"<<"  LeftShiftExpression;
alias BinaryExpression!">>"  SignedRightShiftExpression;
alias BinaryExpression!">>>" UnsignedRightShiftExpression;

alias BinaryExpression!"<<="  LeftShiftAssignExpression;
alias BinaryExpression!">>="  SignedRightShiftAssignExpression;
alias BinaryExpression!">>>=" UnsignedRightShiftAssignExpression;

alias BinaryExpression!">"   GreaterExpression;
alias BinaryExpression!">="  GreaterEqualExpression;
alias BinaryExpression!"<"   LessExpression;
alias BinaryExpression!"<="  LessEqualExpression;

alias BinaryExpression!"<>"   LessGreaterExpression;
alias BinaryExpression!"<>="  LessEqualGreaterExpression;
alias BinaryExpression!"!>"   UnorderedLessEqualExpression;
alias BinaryExpression!"!>="  UnorderedLessExpression;
alias BinaryExpression!"!<"   UnorderedGreaterEqualExpression;
alias BinaryExpression!"!<="  UnorderedGreaterExpression;
alias BinaryExpression!"!<>"  UnorderedEqualExpression;
alias BinaryExpression!"!<>=" UnorderedExpression;

/**
 * Unary Prefix Expression types.
 */
class PrefixUnaryExpression(string operation) : Expression {
	Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
	
	static if(operation == "*") {
		@property
		override bool isLvalue() const {
			return true;
		}
	}
}

alias PrefixUnaryExpression!"&" AddressOfExpression;
alias PrefixUnaryExpression!"*" DereferenceExpression;

alias PrefixUnaryExpression!"++" PreIncrementExpression;
alias PrefixUnaryExpression!"--" PreDecrementExpression;

alias PrefixUnaryExpression!"+" UnaryPlusExpression;
alias PrefixUnaryExpression!"-" UnaryMinusExpression;

alias PrefixUnaryExpression!"!" LogicalNotExpression;
alias PrefixUnaryExpression!"!" NotExpression;

alias PrefixUnaryExpression!"~" BitwiseNotExpression;
alias PrefixUnaryExpression!"~" ComplementExpression;

enum CastType {
	Cast,
	BitCast,
	Pad,
	Trunc,
}

class CastUnaryExpression(CastType T) : Expression {
	Expression expression;
	
	this(Location location, Type type, Expression expression) {
		super(location, type);
		
		this.expression = expression;
	}
}

alias CastUnaryExpression!(CastType.Cast) CastExpression;
alias CastUnaryExpression!(CastType.BitCast) BitCastExpression;
alias CastUnaryExpression!(CastType.Pad) PadExpression;
alias CastUnaryExpression!(CastType.Trunc) TruncateExpression;

// FIXME: make this a statement.
alias PrefixUnaryExpression!"delete" DeleteExpression;

/**
 * Unary Postfix Expression types.
 */
class PostfixUnaryExpression(string operation) : Expression {
	Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
}

alias PostfixUnaryExpression!"++" PostIncrementExpression;
alias PostfixUnaryExpression!"--" PostDecrementExpression;

/**
 * Function call
 */
class CallExpression : Expression {
	Expression callee;
	Expression[] arguments;
	
	this(Location location, Expression callee, Expression[] arguments) {
		super(location);
		
		this.callee = callee;
		this.arguments = arguments;
	}
}

/**
 * Index expression : [index]
 */
class IndexExpression : Expression {
	Expression indexed;
	
	// TODO: this is argument, not parameters.
	Expression[] arguments;
	
	this(Location location, Expression indexed, Expression[] arguments) {
		super(location);
		
		this.indexed = indexed;
		this.arguments = arguments;
	}
}

/**
 * Slice expression : [first .. second]
 */
class SliceExpression : Expression {
	Expression indexed;
	
	Expression[] first;
	Expression[] second;
	
	this(Location location, Expression indexed, Expression[] first, Expression[] second) {
		super(location);
		
		this.indexed = indexed;
		this.first = first;
		this.second = second;
	}
}

/**
 * Parenthese expression.
 */
class ParenExpression : Expression {
	Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
	
	@property
	override bool isLvalue() const {
		return expression.isLvalue;
	}
}

/**
 * Identifier expression
 */
class IdentifierExpression : Expression {
	Identifier identifier;
	
	this(Identifier identifier) {
		super(identifier.location);
		
		this.identifier = identifier;
	}
}

/**
 * Symbol expression.
 * IdentifierExpression that as been resolved.
 */
class SymbolExpression : Expression {
	ExpressionSymbol symbol;
	
	this(Location location, ExpressionSymbol symbol) {
		super(location);
		
		this.symbol = symbol;
	}
	
	invariant() {
		assert(symbol);
	}
	
	@property
	override bool isLvalue() const {
		return !(symbol.isEnum);
	}
}

/**
 * Field access.
 */
class FieldExpression : Expression {
	Expression expression;
	FieldDeclaration field;
	
	this(Location location, Expression expression, FieldDeclaration field) {
		super(location);
		
		this.expression = expression;
		this.field = field;
	}
	
	@property
	override bool isLvalue() const {
		return expression.isLvalue;
	}
}

/**
 * Delegates expressions.
 */
class DelegateExpression : Expression {
	Expression context;
	Expression funptr;
	
	this(Location location, Expression context, Expression funptr) {
		super(location);
		
		this.context = context;
		this.funptr = funptr;
	}
}

/**
 * Virtual dispatch.
 */
class VirtualDispatchExpression : Expression {
	Expression expression;
	MethodDeclaration method;
	
	this(Location location, Expression expression, MethodDeclaration method) {
		super(location);
		
		this.expression = expression;
		this.method = method;
	}
}

/**
 * new
 */
class NewExpression : Expression {
	Expression[] arguments;
	
	this(Location location, Type type, Expression[] arguments) {
		super(location, type);
		
		this.arguments = arguments;
	}
	
	@property
	override bool isLvalue() const {
		return true;
	}
}

/**
 * This
 */
class ThisExpression : Expression {
	this(Location location) {
		super(location);
	}
	
	@property
	override bool isLvalue() const {
		if(auto st = cast(SymbolType) type) {
			if(cast(StructDeclaration) st.symbol) {
				return true;
			}
		}
		
		return false;
	}
}

/**
 * Super
 */
class SuperExpression : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Boolean literal
 */
class BooleanLiteral : CompileTimeExpression {
	bool value;
	
	this(Location location, bool value) {
		super(location, new BooleanType(location));
		
		this.value = value;
	}
}

/**
 * Integer literal
 */
// XXX: remove template parameter here.
class IntegerLiteral(bool isSigned) : CompileTimeExpression {
	static if(isSigned) {
		alias long ValueType;
	} else {
		alias ulong ValueType;
	}
	
	ValueType value;
	
	this(Location location, ValueType value, IntegerType type) {
		super(location, type);
		
		this.value = value;
	}
}

/**
 * Float literal
 */
class FloatLiteral : CompileTimeExpression {
	double value;
	
	this(Location location, real value, FloatType type) {
		super(location, type);
		
		this.value = value;
	}
}

/**
 * Character literal
 */
class CharacterLiteral : CompileTimeExpression {
	string value;
	
	this(Location location, string value, CharacterType type) {
		super(location, type);
		
		this.value = value;
	}
}

/**
 * Factory of literal
 */
auto makeLiteral(T)(Location location, T value) {
	import std.traits;
	static if(is(Unqual!T == bool)) {
		return new BooleanLiteral(location, value);
	} else static if(isIntegral!T) {
		return new IntegerLiteral!(isSigned!T)(location, value, new IntegerType(location, IntegerOf!T));
	} else static if(isFloatingPoint!T) {
		return new FloatLiteral(location, value, new FloatType(location, FloatOf!T));
	} else static if(isSomeChar!T) {
		return new CharacterLiteral(location, [value], new CharacterType(location, CharacterOf!T));
	} else {
		static assert(0, "You can't make litteral for type " ~ T.stringof);
	}
}

/**
 * String literal
 */
class StringLiteral : CompileTimeExpression {
	string value;
	
	this(Location location, string value) {
		auto charType = new CharacterType(location, Character.Char);
		charType.qualifier = TypeQualifier.Immutable;
		
		super(location, new SliceType(location, charType));
		
		this.value = value;
	}
}

/**
 * Array literal
 */
class ArrayLiteral : Expression {
	Expression[] values;
	
	this(Location location, Expression[] values) {
		super(location);
		
		this.values = values;
	}
}

/**
 * Null literal
 */
class NullLiteral : CompileTimeExpression {
	this(Location location) {
		super(location);
	}
	
	this(Location location, Type type) {
		super(location, type);
	}
}

/**
 * __FILE__ literal
 */
class __File__Literal : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * __LINE__ literal
 */
class __Line__Literal : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Delegate literal
 */
class DelegateLiteral : Expression {
	private Statement statement;
	
	this(Statement statement) {
		super(statement.location);
		
		this.statement = statement;
	}
}

/**
 * $
 */
class DollarExpression : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * is expression.
 */
class IsExpression : Expression {
	private Type tested;
	
	this(Location location, Type tested) {
		super(location);
		
		this.tested = tested;
	}
}

/**
 * assert
 */
class AssertExpression : Expression {
	Expression condition;
	Expression message;
	
	this(Location location, Expression condition, Expression message) {
		super(location);
		
		this.condition = condition;
		this.message = message;
	}
}

/**
 * typeid expression.
 */
class TypeidExpression : Expression {
	private Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
}

/**
 * typeid expression with a type as argument.
 */
class StaticTypeidExpression : Expression {
	private Type argument;
	
	this(Location location, Type argument) {
		super(location);
		
		this.argument = argument;
	}
}

/**
 * ambiguous typeid expression.
 */
class IdentifierTypeidExpression : Expression {
	private Identifier argument;
	
	this(Location location, Identifier argument) {
		super(location);
		
		this.argument = argument;
	}
}

/**
 * type.sizeof
 */
class SizeofExpression : Expression {
	Type argument;
	
	this(Location location, Type argument) {
		super(location);
		
		this.argument = argument;
	}
}

/**
 * tuples. Also used for struct initialization.
 */
template TupleExpressionImpl(bool isCompileTime = false) {
	static if(isCompileTime) {
		alias E = CompileTimeExpression;
	} else {
		alias E = Expression;
	}
	
	class TupleExpressionImpl : E {
		E[] values;
	
		this(Location location, E[] values) {
			super(location);
		
			this.values = values;
		}
	}
}

// XXX: required as long as 0 argument instanciation is not possible.
alias TupleExpression = TupleExpressionImpl!false;
alias CompileTimeTupleExpression = TupleExpressionImpl!true;
