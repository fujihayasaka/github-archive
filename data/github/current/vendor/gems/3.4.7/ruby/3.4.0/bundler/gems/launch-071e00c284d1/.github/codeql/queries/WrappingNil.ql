/**
 * @name Nil passed to pkg/errors.Wrap
 * @description There is no point in passing `nil` to pkg/errors.Wrap as it will always return `nil` in that case
 * @kind problem
 * @problem.severity warning
 * @id turboscan/go/wrapping-nil
 * @precision high
 */

import go

/* Gets package for `github.com/pkg/errors`. */
string packagePath() { result = package("github.com/pkg/errors", "") }

/**
 * An equality test which guarantees that an expression is always `nil`.
 */
predicate nilTestGuard(DataFlow::Node g, Expr e, boolean outcome) {
   exists(DataFlow::EqualityTestNode eq, DataFlow::Node otherNode |
     g = eq and
     eq.getAnOperand() = Builtin::nil().getARead() and
     otherNode = eq.getAnOperand() and
     not otherNode = Builtin::nil().getARead() and
     e = otherNode.asExpr() and
     outcome = eq.getPolarity()
   )
}

from DataFlow::Node n
where
  n = any(Function f | f.hasQualifiedName(packagePath(), "Wrap")).getACall().getArgument(0) and
  n = DataFlow::BarrierGuard<nilTestGuard/3>::getABarrierNode()
select n, "This call to errors.Wrap always passes nil"
