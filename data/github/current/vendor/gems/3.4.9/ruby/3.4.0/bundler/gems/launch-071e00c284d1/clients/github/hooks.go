package github

import (
	"context"
	"time"
)

type ClientHooks struct {
	OnBeginRPC            func(ctx context.Context, opname, optype string)
	OnStartPerformRequest func(ctx context.Context, opname, optype string, attempt int)
	OnDonePerformRequest  func(ctx context.Context, opname, optype string, res *ReqResult)
	OnStartHandleResponse func(ctx context.Context, opname, optype string)
	OnDoneHandleResponse  func(ctx context.Context, opname, optype string, res *RespResult)
	OnEndRPC              func(ctx context.Context, opname, optype string, res *RPCResult)
}

func (ch *ClientHooks) ensureDefaults() {
	if ch.OnBeginRPC == nil {
		ch.OnBeginRPC = func(ctx context.Context, opname, optype string) {}
	}
	if ch.OnStartPerformRequest == nil {
		ch.OnStartPerformRequest = func(ctx context.Context, opname, optype string, attempt int) {}
	}
	if ch.OnDonePerformRequest == nil {
		ch.OnDonePerformRequest = func(ctx context.Context, opname, optype string, res *ReqResult) {}
	}
	if ch.OnStartHandleResponse == nil {
		ch.OnStartHandleResponse = func(ctx context.Context, opname, optype string) {}
	}
	if ch.OnDoneHandleResponse == nil {
		ch.OnDoneHandleResponse = func(ctx context.Context, opname, optype string, res *RespResult) {}
	}
	if ch.OnEndRPC == nil {
		ch.OnEndRPC = func(ctx context.Context, opname, optype string, res *RPCResult) {}
	}
}

type ReqResult struct {
	Status   string
	Err      error
	Attempt  int
	Duration time.Duration
}

type RespResult struct {
	Status        string
	Err           error
	Code, Attempt int
	Duration      time.Duration
}

type RPCResult struct {
	Status        string
	Code, Attempt int
	Duration      time.Duration
}

func resultStatus(err error) string {
	if err != nil {
		return ErrorStatusValue
	}

	return ""
}
