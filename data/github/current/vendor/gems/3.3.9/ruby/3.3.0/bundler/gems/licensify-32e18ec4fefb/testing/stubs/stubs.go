// Package stubs provides helper functions to create stubs for testing.
package stubs

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"strconv"
	"time"

	enterprise_accountv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	licensingv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/licensing/v0"
	repositoriesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v1"
	repositoriesv2 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v2"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	licensifyRepositoriesV1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// NewRandomID returns a random uint64.
func NewRandomID() uint64 {
	const maxID = 1000000
	id, _ := rand.Int(rand.Reader, big.NewInt(maxID))
	return id.Uint64()
}

// NewRandomInt32ID returns a random int32 id
// It type casts the random uint64 to an int32 so we can ignore the overflow lint in a single place
// As long as maxID above is less than 2^32, we will not overflow
// If you're using this, consider making updates so that a uint64 can be used instead
// like maybe update a hydro schema to use uint64 instead of int64 or int32
func NewRandomInt32ID() int32 {
	return int32(NewRandomID()) //nolint:gosec // maxID is less than 2^32
}

// NewRandomRepoGlobalID returns a random repository global ID.
func NewRandomRepoGlobalID() string {
	return NewRepoGlobalID(NewRandomID())
}

// NewRepoGlobalID returns a global ID given a repository ID.
func NewRepoGlobalID(id uint64) string {
	return fmt.Sprintf("gid://git-hub/Repository/%d", id)
}

// NewCustomerProto returns a new customer proto.
func NewCustomerProto() *proto.Customer {
	return &proto.Customer{
		Id:                 NewRandomID(),
		SdlcLicensingModel: 1,
		SdlcTrial:          false,
	}
}

// UpsertCustomerProto returns a upsert customer request proto.
func UpsertCustomerProto() *proto.UpsertCustomerRequest {
	return &proto.UpsertCustomerRequest{
		Customer: &proto.Customer{
			Id:                 NewRandomID(),
			SdlcLicensingModel: 1,
		},
	}
}

// NewCustomerLicenseProto returns a new customer license proto.
func NewCustomerLicenseProto() *proto.CustomerLicense {
	timeNow := time.Now().Truncate(time.Second)
	idDeprecated := NewRandomID()
	id := strconv.FormatUint(idDeprecated, 10)
	return &proto.CustomerLicense{
		CustomerId:    NewRandomID(),
		Product:       proto.Product_PRODUCT_SDLC,
		LicenseStatus: proto.LicenseStatus_LICENSE_STATUS_ACTIVE,
		Licensee: &proto.Licensee{
			Type:         proto.LicenseeType_LICENSEE_TYPE_USER,
			IdDeprecated: idDeprecated,
			GlobalId:     NewRandomRepoGlobalID(),
			Id:           id,
		},
		Enablements: []*proto.CustomerLicenseEnablement{
			{
				Type:          proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_ORG,
				Reason:        proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP,
				EnablementIds: []uint64{NewRandomID()},
			},
		},
		ExpiresAt: timestamppb.New(timeNow.Add(90 * 24 * time.Hour)),
		SuspendedAt: &timestamppb.Timestamp{
			Seconds: 1728675888,
		},
	}
}

// NewProductEnablementProto returns a new product enablement proto.
func NewProductEnablementProto() *proto.ProductEnablement {
	timeNow := time.Now().Truncate(time.Second)
	enablementID := NewRandomID()
	return &proto.ProductEnablement{
		CustomerId:     NewRandomID(),
		Product:        proto.Product_PRODUCT_GHAS,
		EnablementId:   enablementID,
		EnablementType: proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_REPO,
		GlobalId:       NewRepoGlobalID(enablementID),
		EnabledAt:      timestamppb.New(timeNow),
	}
}

// NewMembershipUpdateHydroMsg returns a new membership update hydro message for testing.
func NewMembershipUpdateHydroMsg(context githubv1.MembershipUpdate_Context, action githubv1.MembershipUpdate_Action) *githubv1.MembershipUpdate {
	return &githubv1.MembershipUpdate{
		CustomerId: int64(NewRandomInt32ID()),
		Actor: &entities.User{
			Id:    uint32(NewRandomInt32ID()),
			Login: "octocat",
		},
		Action: action,
		User: &entities.User{
			Id:    uint32(NewRandomInt32ID()),
			Login: "monalisa",
		},
		GroupId: NewRandomID(),
		Context: context,
	}
}

// NewEnterpriseManagedIdentitySuspendedHydroMsg returns a new enterprise managed identity suspended hydro message for testing.
func NewEnterpriseManagedIdentitySuspendedHydroMsg() *licensingv0.EnterpriseManagedIdentitySuspended {
	return &licensingv0.EnterpriseManagedIdentitySuspended{
		Business: &entities.Business{
			CustomerId: int64(NewRandomInt32ID()),
		},
		SuspendedAt: &timestamppb.Timestamp{
			Seconds: 1728675888,
		},
		UserId: int64(NewRandomInt32ID()),
	}
}

// NewEnterpriseManagedIdentityUnsuspendedHydroMsg returns a new enterprise managed identity unsuspended hydro message for testing.
func NewEnterpriseManagedIdentityUnsuspendedHydroMsg() *licensingv0.EnterpriseManagedIdentityUnsuspended {
	return &licensingv0.EnterpriseManagedIdentityUnsuspended{
		Business: &entities.Business{
			CustomerId: int64(NewRandomInt32ID()),
		},
		UserId: int64(NewRandomInt32ID()),
	}
}

// NewOrganizationAddHydroMsg returns a new organization add hydro message for testing.
func NewOrganizationAddHydroMsg() *enterprise_accountv0.OrganizationAdd {
	return &enterprise_accountv0.OrganizationAdd{
		Organization: &entities.Organization{
			Id: NewRandomID(),
		},
		Enterprise: &entities.Business{
			CustomerId: int64(NewRandomInt32ID()),
		},
	}
}

// NewOrganizationRemoveHydroMsg returns a new organization remove hydro message for testing.
func NewOrganizationRemoveHydroMsg() *enterprise_accountv0.OrganizationRemove {
	return &enterprise_accountv0.OrganizationRemove{
		Organization: &entities.Organization{
			Id: NewRandomID(),
		},
		Enterprise: &entities.Business{
			CustomerId: int64(NewRandomInt32ID()),
		},
	}
}

// NewOrganizationTransferHydroMsg returns a new organization transfer hydro message for testing.
func NewOrganizationTransferHydroMsg() *enterprise_accountv0.OrganizationTransfer {
	return &enterprise_accountv0.OrganizationTransfer{
		SourceEnterprise: &entities.Business{
			CustomerId: int64(NewRandomInt32ID()),
		},
		DestinationEnterprise: &entities.Business{
			CustomerId: int64(NewRandomInt32ID()),
		},
	}
}

// NewOrganizationDestroyHydroMsg returns a new organization destroy hydro message for testing.
func NewOrganizationDestroyHydroMsg() *githubv1.UserDestroy {
	return &githubv1.UserDestroy{
		User: &entities.User{
			Id:   uint32(NewRandomInt32ID()),
			Type: entities.User_ORGANIZATION,
		},
		OrganizationCustomerId: int64(NewRandomInt32ID()),
	}
}

// NewOrganizationUpgradeHydroMsg returns a new organization upgrade hydro message for testing.
func NewOrganizationUpgradeHydroMsg() *enterprise_accountv0.OrganizationUpgrade {
	return &enterprise_accountv0.OrganizationUpgrade{
		Enterprise: &entities.Business{
			Id:         NewRandomID(),
			CustomerId: int64(NewRandomInt32ID()),
		},
		Organization: &entities.Organization{
			Id: NewRandomID(),
		},
		OrganizationPreviousCustomerId: int64(NewRandomInt32ID()),
		Status:                         enterprise_accountv0.OrganizationUpgrade_PURCHASE_UPGRADED,
	}
}

// NewOrganizationRestoreHydroMsg returns a new organization restore hydro message for testing.
func NewOrganizationRestoreHydroMsg() *githubv1.OrganizationRestore {
	return &githubv1.OrganizationRestore{
		Organization: &entities.Organization{
			Id: NewRandomID(),
		},
		CustomerId: int64(NewRandomInt32ID()),
	}
}

// NewBillingPlanChangeHydroMsg returns a new billing plan change hydro message for testing.
// The message is sent when a standalone org upgrades/downgrades between free to Team.
func NewBillingPlanChangeHydroMsg() *githubv1.BillingPlanChange {
	return &githubv1.BillingPlanChange{
		PreviousPlan: "free",
		CurrentPlan:  "business",
		Action:       githubv1.BillingPlanChange_UPGRADE,
		Organization: &entities.Organization{
			Id: NewRandomID(),
		},
	}
}

// NewUserDestroyHydroMsg returns a new user destroy hydro message for testing.
func NewUserDestroyHydroMsg() *githubv1.UserDestroy {
	return &githubv1.UserDestroy{
		User: &entities.User{
			Id:   uint32(NewRandomInt32ID()),
			Type: entities.User_USER,
		},
	}
}

// NewRepositoryCollaboratorAddHydroMsg returns a new repository add member hydro message for testing.
func NewRepositoryCollaboratorAddHydroMsg() *githubv1.RepositoryAddMember {
	return &githubv1.RepositoryAddMember{
		Repository: &entities.Repository{
			Id:         uint32(NewRandomInt32ID()),
			Visibility: entities.Repository_PRIVATE,
			IsFork:     false,
			ParentId:   0,
		},
		Member: &entities.User{
			Id: uint32(NewRandomInt32ID()),
		},
		RepositoryOwnerCustomerId:     int64(NewRandomInt32ID()),
		IsRepositoryAdvisoryWorkspace: false,
	}
}

// NewRepositoryVisibilityChangedHydroMsg returns a new repository visibility changed hydro message for testing.
func NewRepositoryVisibilityChangedHydroMsg() *repositoriesv1.VisibilityChanged {
	return &repositoriesv1.VisibilityChanged{
		RepositoryId:  int64(NewRandomInt32ID()),
		NewVisibility: repositoriesv1.VisibilityChanged_PRIVATE,
	}
}

// NewRepositoryDeletedHydroMsg returns a new repository deleted hydro message for testing.
func NewRepositoryDeletedHydroMsg() *repositoriesv1.Deleted {
	return &repositoriesv1.Deleted{
		RepositoryId: int64(NewRandomInt32ID()),
		ActorId:      &wrapperspb.Int64Value{Value: int64(NewRandomInt32ID())},
	}
}

// NewRepositoryFromHydroEntity returns a new repository from a hydro entity.
func NewRepositoryFromHydroEntity() *licensifyRepositoriesV1.Repository {
	return &licensifyRepositoriesV1.Repository{
		Id:                  NewRandomID(),
		Visibility:          licensifyRepositoriesV1.Repository_VISIBILITY_PRIVATE,
		ParentId:            0,
		OwnerCustomerId:     int64(NewRandomInt32ID()),
		IsAdvisoryWorkspace: false,
		IsFork:              false,
		IsActive:            true,
	}
}

// NewOrganizationSoftDeleteHydroMsg returns a new membership update hydro message for testing.
func NewOrganizationSoftDeleteHydroMsg() *githubv1.OrganizationSoftDelete {
	return &githubv1.OrganizationSoftDelete{
		CustomerId: int64(NewRandomInt32ID()),
		Organization: &entities.Organization{
			Id: NewRandomID(),
		},
	}
}

// NewRepositoryRestoredHydroMsg returns a new repository restored hydro message for testing.
func NewRepositoryRestoredHydroMsg() *repositoriesv2.Restored {
	return &repositoriesv2.Restored{
		RepositoryId: int64(NewRandomInt32ID()),
	}
}
