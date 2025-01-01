package newsiesservice

import (
	"strings"

	"github.com/hashicorp/go-multierror"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	"github.com/github/notifyd/internal/pkg/validations"
)

func watchValidation(refType string, fields []subscriptions.CustomField) *validations.Validation {
	v := validations.New()
	v.Add(refTypeValidator(refType))
	v.Add(subscriptionsCustomFieldsValidator(fields))

	return v
}

func ignoreValidation(refType string, fields []routing.CustomField) *validations.Validation {
	v := validations.New()
	v.Add(refTypeValidator(refType))
	v.Add(settingsCustomFieldsValidator(fields))

	return v
}

func unwatchValidation(refType string) *validations.Validation {
	v := validations.New()
	v.Add(refTypeValidator(refType))

	return v
}

func refTypeValidator(refType string) func() error {
	return func() error {
		if !strings.EqualFold(refType, RepositoryRefType) {
			return errors.New("Invalid ref type, repository only supported")
		}

		return nil
	}
}

// settingsCustomFieldsValidator makes sure that the proper custom fields are included by the
// integrator.
//
// More on this in ADR34 for data mapping between newsies and Notifyd
func settingsCustomFieldsValidator(fields []routing.CustomField) func() error {
	return func() error {
		var err error
		ownerType := false
		ownerID := false

		for _, f := range fields {
			if ownerType && ownerID {
				return nil
			}

			if !ownerType && strings.EqualFold(f.Name, OwnerTypeName) {
				ownerType = true
			}

			if !ownerID && strings.EqualFold(f.Name, OwnerIDName) {
				ownerID = true
			}
		}

		if !ownerType {
			err = multierror.Append(errors.New("not found owner_type custom field"))
		}

		if !ownerID {
			err = multierror.Append(errors.New("not found owner_id custom field"))
		}

		return err
	}
}

// subscriptionsCustomFieldsValidator makes sure that the proper custom fields are included by the
// integrator.
//
// More on this in ADR34 for data mapping between newsies and Notifyd
func subscriptionsCustomFieldsValidator(fields []subscriptions.CustomField) func() error {
	return func() error {
		var err error
		ownerType := false
		ownerID := false

		for _, f := range fields {
			if ownerType && ownerID {
				return nil
			}

			if !ownerType && strings.EqualFold(f.Name, OwnerTypeName) {
				ownerType = true
			}

			if !ownerID && strings.EqualFold(f.Name, OwnerIDName) {
				ownerID = true
			}
		}

		if !ownerType {
			err = multierror.Append(errors.New("not found owner_type custom field"))
		}

		if !ownerID {
			err = multierror.Append(errors.New("not found owner_id custom field"))
		}

		return err
	}
}
