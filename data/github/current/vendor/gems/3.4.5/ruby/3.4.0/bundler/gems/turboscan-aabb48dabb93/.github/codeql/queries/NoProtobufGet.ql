/**
 * @name Protobuf getter used
 * @description The generated Twirp code ensures that the request is not nil so there is no need to use the getters that check for nil.
 * @kind problem
 * @problem.severity warning
 * @id turboscan/go/protobuf-getter-used
 * @precision high
 */

import go

from SelectorExpr se, Type resultType
where
  // The result type is a pointer to a struct
  resultType = se.getBase().getType().(PointerType).getBaseType() and
  // The type is defined in the generated protobuf file (bit of a hack, but precise in this repo)
  resultType.getEntity().getDeclaration().getFile().getBaseName().matches("%.pb.go") and
  // The call is not within that generated protobuf file
  not se.getFile().getBaseName().matches("%.pb.go") and
  // The called method starts with 'Get'
  se.getSelector().getName().matches("Get%")
select se, "There is no need to use the Get methods, prefer accessing the struct fields directly"
