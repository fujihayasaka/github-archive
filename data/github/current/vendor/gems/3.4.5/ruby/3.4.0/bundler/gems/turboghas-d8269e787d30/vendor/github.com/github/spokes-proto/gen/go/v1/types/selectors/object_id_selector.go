package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewObjectIDSelector(oids ...*types.ObjectID) *ObjectIDSelector {
	return &ObjectIDSelector{Oids: oids}
}

func (o *ObjectIDSelector) Validate() error {
	if o == nil {
		return nil
	}

	if len(o.Oids) == 0 {
		return twirp.RequiredArgumentError("oids")
	}

	for _, oid := range o.GetOids() {
		if err := oid.Validate(); err != nil {
			return err
		}
	}

	return nil
}
