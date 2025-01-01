/**
 * @name Span context not used
 * @description A context returned from a StartSpan call is not being used 
 * @kind problem
 * @problem.severity warning
 * @id turboscan/go/span-context-not-used
 * @precision high
 */

import go

from CallExpr call, Variable ctxVar, Expr laterCtxUse
where
  // Find a call to StartSpan
  call.getCalleeName() = "StartSpan" and
  // which gets passed the context
  call.getArgument(0) = ctxVar.getARead().asExpr() and
  // but discards the returned Context
  exists (Assignment assign, BlankIdent blank | 
    assign.getAChild() = call and
    assign.getLhs(0) = blank
    ) and

  // But the context variable is used afterwards
  laterCtxUse = ctxVar.getARead().asExpr() and
  laterCtxUse.getLocation().getEndLine() > call.getLocation().getEndLine()
select laterCtxUse, "Since there is an earlier $@ you should use its return value here instead of the original `Context`.", call, "call to StartSpan"