/**
 * @name Defer in loop
 * @description A deferred statement in a for loop will not execute until the end of the function.
 *              This can lead to unintentionally holding resources open like file handles or database transactions.
 * @kind problem
 * @problem.severity warning
 * @id turboscan/go/defer-in-for-loop
 * @precision high
 */

import go

from LoopStmt loop, DeferStmt defer
where loop.getBody().getAChildStmt+() = defer
select defer, "This defer statement is in a $@.", loop, "loop"
