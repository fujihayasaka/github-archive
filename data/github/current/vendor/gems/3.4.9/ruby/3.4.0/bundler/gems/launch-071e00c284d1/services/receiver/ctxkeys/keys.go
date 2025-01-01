package ctxkeys

import "github.com/github/launch/pkg/mu/ctxkey"

// ThresholdContextKey points to this route's timing threshold
var ThresholdContextKey = ctxkey.New("receiver_threshold_key")
