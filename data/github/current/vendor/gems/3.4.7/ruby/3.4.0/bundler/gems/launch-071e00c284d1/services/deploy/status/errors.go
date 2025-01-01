package status

import (
	svcerr "github.com/github/launch/services/errors"
)

// ErrPostbackDenied means the postback urls are invalid because the build has completed
var ErrPostbackDenied = svcerr.NewPermissionDeniedError("postback url has expired")
