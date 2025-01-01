package tenancy

/*
Set of tools to save and retrieve a Tenant from a Context
Note that it is preferred to pass a Tenant instance explicitly, but in some cases, like
integrations with HTTP frameworks, the only way to pass it is inside a Context object
*/

import (
	"context"
	"errors"
)

type ctxKey struct{}

// box helps us to save a Tenant in the context and then extract it
// Since tenant is an interface, we use the box with a hint (the actual type)
// to properly cast the Tenant instance outside the context
type box struct {
	tenant Tenant
	hint   string
}

func wrap(tenant Tenant) box {
	switch tenant.(type) {
	case SingleTenant:
		return box{tenant: tenant, hint: "single"}
	case MultiTenant:
		return box{tenant: tenant, hint: "multi"}
	}

	return box{tenant: tenant, hint: "unknown"}
}

func (b box) unwrap() (Tenant, error) {
	switch b.hint {
	case "single":
		return b.tenant.(SingleTenant), nil //nolint:forcetypeassert,revive // type known from hint
	case "multi":
		return b.tenant.(MultiTenant), nil //nolint:forcetypeassert,revive // type known from hint
	}

	return nil, errors.New("unknown tenant type inside context")
}

// ContextWithTenant creates a new Context with the given Tenant inside it
func ContextWithTenant(ctx context.Context, tenant Tenant) context.Context {
	return context.WithValue(ctx, ctxKey{}, wrap(tenant))
}

// FromContext extracts a Tenant from a Context
func FromContext(ctx context.Context) (Tenant, error) {
	if value := ctx.Value(ctxKey{}); value != nil {
		if box, ok := value.(box); ok {
			return box.unwrap()
		}
	}

	return nil, errors.New("no tenant found in context")
}
