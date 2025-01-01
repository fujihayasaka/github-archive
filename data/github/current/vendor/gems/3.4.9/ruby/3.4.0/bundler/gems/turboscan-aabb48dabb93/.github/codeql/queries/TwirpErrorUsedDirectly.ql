/**
 * @name Twirp error used directly
 * @description Detects calls to error creattors in the Towrip library.
 *              We want to use our internal helpers instead, since they provide better stack traces.
 * @kind problem
 * @problem.severity warning
 * @id turboscan/go/twirp-error-used-directly
 * @precision high
 */

import go

class DisallowedTwirpLibraryErrorCreator extends Function {
   DisallowedTwirpLibraryErrorCreator() {
      
      // We just identify any function in the Twirp paackage ...
      this.getPackage().getPath() = "github.com/twitchtv/twirp" and
      // ... that has exactly one return value ...
      this.getNumResult() = 1 and
      // ... of type Error.
      this.getResultType(0).getName() = "Error" and
      // InternalErrorWith is allowed since it wraps an existing error.
      this.getName() != "InternalErrorWith" and
      // WithMeta is allowed since it modifies an existing error
      this.getName() != "WithMeta"
   }
}

class AllowedCallingPackage extends Package {
   AllowedCallingPackage() {
      // Twirp is allowed to call itself
      this.getPath() = "github.com/twitchtv/twirp" or
      // The generated protobuf code is allowed
      this.getPath() = "github.com/github/turboscan/ts/proto" or
      // The generated code for calling the monolith API code is allowed 
      this.getPath().substring(0, 46) = "github.com/github/turboscan/ts/monolith_twirp/" or
      // Our internal helpers are allowed
      this.getPath() = "github.com/github/turboscan/ts/twirp/twerrors"
   }
}

 from CallExpr call, DisallowedTwirpLibraryErrorCreator target
 where
   call.getTarget() = target and
   not exists (AllowedCallingPackage pkg | call.getEnclosingFunction().getScope().getOuterScope+().(PackageScope).getPackage() = pkg )

select call, "Do not call `$@` from the Twirp library directly to create a Twirp error, use our internal helpers in ts/twirp/twerrors/errors.go instead. Errors created from the Twirp library do not provide proper stack traces.", target.getName(), target.getName()
