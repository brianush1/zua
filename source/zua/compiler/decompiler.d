module zua.compiler.decompiler;

// version(assert) {

// 	private final class Decompiler {

// 		string buffer;

// 		void compile(Stat stat) {
// 			if (auto s = cast(AssignStat) stat) compilev(s);
// 			else if (auto s = cast(ExprStat) stat) compilev(s);
// 			else if (auto s = cast(Block) stat) compilev(s);
// 			else if (auto s = cast(DeclarationStat) stat) compilev(s);
// 			else if (auto s = cast(WhileStat) stat) compilev(s);
// 			else if (auto s = cast(RepeatStat) stat) compilev(s);
// 			else if (auto s = cast(IfStat) stat) compilev(s);
// 			else if (auto s = cast(NumericForStat) stat) compilev(s);
// 			else if (auto s = cast(ForeachStat) stat) compilev(s);
// 			else if (auto s = cast(ReturnStat) stat) compilev(s);
// 			else if (auto s = cast(AtomicStat) stat) compilev(s);
// 			else assert(0);
// 		}

// 		void compile(Expr expr) {
// 			if (auto e = cast(AtomicExpr) expr) compilev(e);
// 			else if (auto e = cast(NumberExpr) expr) compilev(e);
// 			else if (auto e = cast(StringExpr) expr) compilev(e);
// 			else if (auto e = cast(FunctionExpr) expr) compilev(e);
// 			else if (auto e = cast(BinaryExpr) expr) compilev(e);
// 			else if (auto e = cast(UnaryExpr) expr) compilev(e);
// 			else if (auto e = cast(TableExpr) expr) compilev(e);
// 			else if (auto e = cast(LvalueExpr) expr) compile(e);
// 			else if (auto e = cast(BracketExpr) expr) compilev(e);
// 			else if (auto e = cast(CallExpr) expr) compilev(e);
// 			else assert(0);
// 		}

// 		void compile(LvalueExpr expr) {
// 			if (auto e = cast(GlobalExpr) expr) compilev(e);
// 			else if (auto e = cast(LocalExpr) expr) compilev(e);
// 			else if (auto e = cast(UpvalueExpr) expr) compilev(e);
// 			else if (auto e = cast(IndexExpr) expr) compilev(e);
// 			else assert(0);
// 		}

// 		void compilev(AssignStat stat) {

// 		}

// 	}

// }