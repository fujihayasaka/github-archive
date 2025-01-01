package references

import (
	"fmt"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	"github.com/github/spokes-proto/gen/go/v1/extensions"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

func NewResolveReferencesRequest(reqCtx *types.RequestContext, repository *types.Repository, refs ...*types.Reference) *ResolveReferencesRequest {
	return &ResolveReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		References:     refs,
	}
}

func (req *ResolveReferencesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	references := req.GetReferences()
	if len(references) < 1 {
		return twirp.RequiredArgumentError("references")
	}

	desc := req.ProtoReflect().Descriptor().Fields().ByName("references")
	refLimit := int(proto.GetExtension(desc.Options(), extensions.E_Limit).(uint32))
	if refLimit > 0 && len(references) > refLimit {
		return twirp.InvalidArgumentError("references", fmt.Sprintf("may contain up to %d items", refLimit))
	}

	// Note: The references will be validated individually. See the docs for
	// ResolveReferences for details about how these validation errors will
	// be handled.

	return nil
}

func NewListReferencesRequestWithUniversalSelector(reqCtx *types.RequestContext, repository *types.Repository, cursor *types.Cursor) *ListReferencesRequest {
	return &ListReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListReferencesRequest_UniversalSelector{UniversalSelector: selectors.NewUniversalSelector()},
		Cursor:         cursor,
	}
}

func NewListReferencesRequestWithPrefixSelector(reqCtx *types.RequestContext, repository *types.Repository, prefixes *selectors.PrefixSelector, cursor *types.Cursor) *ListReferencesRequest {
	return &ListReferencesRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Selector:       &ListReferencesRequest_PrefixSelector{PrefixSelector: prefixes},
		Cursor:         cursor,
	}
}

func (req *ListReferencesRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ListReferencesRequest_UniversalSelector:
		if s.UniversalSelector == nil {
			return twirp.RequiredArgumentError("selector.universal_selector")
		}

		if err := s.UniversalSelector.Validate(); err != nil {
			return err
		}
	case *ListReferencesRequest_PrefixSelector:
		if s.PrefixSelector == nil {
			return twirp.RequiredArgumentError("selector.prefix_selector")
		}

		if err := s.PrefixSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func (req *GetDefaultBranchRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *ListReferencesWithDetailsRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	switch s := req.GetSelector().(type) {
	case *ListReferencesWithDetailsRequest_UniversalSelector:
		if s.UniversalSelector == nil {
			return twirp.RequiredArgumentError("selector.universal_selector")
		}

		if err := s.UniversalSelector.Validate(); err != nil {
			return err
		}
	case *ListReferencesWithDetailsRequest_RefGlobSelector:
		if s.RefGlobSelector == nil {
			return twirp.RequiredArgumentError("selector.ref_glob_selector")
		}

		if err := s.RefGlobSelector.Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("selector")
	}

	return nil
}

func (req *UpdateDefaultBranchRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetNewValue() == nil {
		return twirp.RequiredArgumentError("new_value")
	}

	if err := req.GetNewValue().Validate(); err != nil {
		return err
	}

	if err := req.GetNewValue().ValidateFormat(); err != nil {
		return err
	}

	if req.GetNewValue().IsDefaultBranch() {
		return twirp.InvalidArgumentError("new_value", "cannot be HEAD")
	}

	return nil
}

func (req *ReferencesExistRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}
