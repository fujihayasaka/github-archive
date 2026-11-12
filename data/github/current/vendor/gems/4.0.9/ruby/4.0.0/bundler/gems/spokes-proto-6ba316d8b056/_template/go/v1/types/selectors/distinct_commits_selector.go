package selectors

import (
	"fmt"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewDistinctCommitsSelector(ref *types.Reference, oid *types.ObjectID, exclude_oids ...*types.ObjectID) *DistinctCommitsSelector {
	return &DistinctCommitsSelector{
		Reference:   ref,
		Oid:         oid,
		ExcludeOids: exclude_oids,
	}
}

func (r *DistinctCommitsSelector) Validate() error {
	if r == nil {
		return nil
	}

	if r.GetReference() == nil {
		return twirp.RequiredArgumentError("reference")
	}

	if err := r.GetReference().ValidateFormat(); err != nil {
		return err
	}

	if err := r.GetOid().Validate(); err != nil {
		return err
	}

	desc := r.ProtoReflect().Descriptor().Fields().ByName("exclude_oids")
	oidLimit := int(proto.GetExtension(desc.Options(), extensions.E_Limit).(uint32))
	oidCount := len(r.GetExcludeOids())
	if oidLimit > 0 && oidCount > oidLimit {
		return twirp.InvalidArgumentError("exclude_oids", fmt.Sprintf("may contain up to %d items", oidLimit))
	}

	for _, oid := range r.GetExcludeOids() {
		if err := oid.Validate(); err != nil {
			return err
		}
	}

	return nil
}
