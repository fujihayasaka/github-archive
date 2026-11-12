package types

import (
	"net"

	"github.com/twitchtv/twirp"
)

func NewRequestContext(qualityOfService RequestContext_QualityOfService, opts ...RequestContextOption) *RequestContext {
	ret := &RequestContext{
		QualityOfService: qualityOfService,
	}

	for _, opt := range opts {
		opt(ret)
	}

	return ret
}

type RequestContextOption func(*RequestContext)

func WithUserID(userID uint64) RequestContextOption {
	return func(r *RequestContext) {
		r.UserId = userID
	}
}

func WithRealIPAddr(addr string) RequestContextOption {
	return func(r *RequestContext) {
		r.RealIp = addr
	}
}

func WithRealIP(ip net.IP) RequestContextOption {
	return func(r *RequestContext) {
		r.RealIp = ip.String()
	}
}

func WithReadUncommitted() RequestContextOption {
	return func(r *RequestContext) {
		r.ReadUncommitted = true
	}
}

func WithTransactionContext(transactionContext *TransactionContext) RequestContextOption {
	return func(r *RequestContext) {
		r.TransactionState = transactionContext.GetTransactionState()
	}
}

func WithTransactionState(transactionState []byte) RequestContextOption {
	return func(r *RequestContext) {
		r.TransactionState = transactionState
	}
}

func WithReadAfterWrite() RequestContextOption {
	return func(r *RequestContext) {
		r.ReadAfterWrite = true
	}
}

// Validate checks that the RequestContext is valid.
//
// In the future, this will be replaced by ValidatePreview.
func (r *RequestContext) Validate() error {
	return nil
}

// ValidatePreview is the set of rules that will be enforced on RequestContext in the future.
func (r *RequestContext) ValidatePreview() error {
	switch r.GetQualityOfService() {
	case RequestContext_QUALITY_OF_SERVICE_NO_DELAY:
	case RequestContext_QUALITY_OF_SERVICE_DELAYABLE:
	case RequestContext_QUALITY_OF_SERVICE_FAIL_FAST:
	default:
		return twirp.InvalidArgumentError("request_context.quality_of_service", "must be set")
	}

	if r.GetRealIp() != "" {
		// Gitmon parses the IP address, so it needs to be valid.
		if net.ParseIP(r.GetRealIp()) == nil {
			return twirp.InvalidArgumentError("request_context.real_ip", "must be an IPv4 or IPv6 address")
		}
	}

	return nil
}
