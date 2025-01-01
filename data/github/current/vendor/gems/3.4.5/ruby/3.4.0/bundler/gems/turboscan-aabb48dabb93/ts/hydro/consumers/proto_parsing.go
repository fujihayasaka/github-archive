package consumers

import (
	"time"

	security_center_hydro_v1 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v1"
	security_center_hydro_v1_entities "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v1/entities"

	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"

	"github.com/SamuelTissot/sqltime"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/pkg/errors"

	pb "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/auditlog"
	"github.com/github/turboscan/ts/validate"
)

var ErrMissingField = errors.New("message is missing a required field")

// DeliveryFromProtoBytes translates a buffer containing a protobuf
// Analysis into an instance of ts.Delivery.
func DeliveryFromProtoBytes(bytes []byte) (*ts.Delivery, error) {
	var msg pb.Analysis

	err := UnwrapAnalysisMessage(bytes, &msg)
	if err != nil {
		return nil, errors.Wrap(err, "can't decode bytes into proto Analysis msg")
	}

	return DeliveryFromProto(&msg)
}

// DeliveryFromProto returns a Delivery object from an Analysis
// protobuf message
func DeliveryFromProto(msg *pb.Analysis) (*ts.Delivery, error) {
	if !validate.IsCommitOid(msg.CommitOid) {
		return nil, errors.New("commitoid is not valid")
	}

	if msg.HeadCommitOid != "" && !validate.IsCommitOid(msg.HeadCommitOid) {
		return nil, errors.New("headcommitoid is not valid")
	}

	if !validate.IsRef(msg.Ref) {
		return nil, errors.New("ref is not a fully qualified ref")
	}

	if len(msg.Ref) > ts.RefMaxSize {
		return nil, errors.New("ref is too long")
	}

	if msg.RepositoryId == 0 {
		return nil, errors.New("repositoryid cannot be empty")
	}

	if msg.AnalysisKey == "" {
		return nil, errors.New("analysis key cannot be empty")
	}

	sarifID, ok := ts.NewSarifID(msg.SarifId)
	if !ok {
		return nil, errors.New("invalid sarif_id")
	}

	env := ts.AnalysisEnv{}
	var rawEnv = "{}"
	if msg.Environment != "" {
		rawEnv = msg.Environment
	}

	_ = env.Scan(rawEnv)

	outdatedConfiguration := ts.OutdatedConfiguration{}
	if msg.OutdatedConfiguration != nil {
		outdatedConfiguration.Category = ts.ToCategory(msg.OutdatedConfiguration.Category)
		outdatedConfiguration.ToolName = ts.ToToolName(msg.OutdatedConfiguration.ToolName)
	}

	var auditLogContext auditlog.AuditLogContext
	if msg.AuditLogContext != nil {
		auditLogContext = auditlog.AuditLogContext{
			OrgID:      uint64(msg.AuditLogContext.OrgId),
			Org:        msg.AuditLogContext.Org,
			BusinessID: uint64(msg.AuditLogContext.BusinessId),
			Business:   msg.AuditLogContext.Business,
		}
	}

	delivery := ts.Delivery{
		CommitOid:             ts.ToSha(msg.CommitOid),
		HeadCommitOid:         ts.ToShaPtr(msg.HeadCommitOid),
		Ref:                   msg.Ref,
		RepositoryID:          ts.RepositoryEID(msg.RepositoryId),
		RepositoryNWO:         ts.ToRepositoryNWO(msg.RepoNwo),
		OwnerID:               ts.OwnerEID(msg.OwnerId),
		RequestID:             ts.ToRequestID(msg.RequestId),
		AnalysisKey:           ts.ToAnalysisKey(msg.AnalysisKey),
		Environment:           env,
		CheckoutURI:           ts.ToCheckoutURI(msg.CheckoutUri),
		WorkflowRunID:         ts.WorkflowRunEID(msg.WorkflowRunId),
		WorkflowRunAttempt:    ts.WorkflowRunAttempt(msg.WorkflowRunAttempt),
		SarifPath:             msg.SarifUri,
		SarifID:               sarifID,
		BuildStartedAt:        convertTime(msg.BuildStartAt),
		UploadStartedAt:       convertTime(msg.UploadStartedAt),
		UploadFinishedAt:      convertTime(msg.UploadFinishedAt),
		HydroEnqueuedAt:       convertTime(msg.HydroEnqueuedAt),
		SourceRepositoryID:    ts.RepositoryEID(msg.SourceRepositoryId),
		TrackStatus:           msg.TrackStatus,
		OutdatedConfiguration: outdatedConfiguration,
		CheckRunIds:           msg.CheckRunIds,
		AuditLogContext:       &auditLogContext,
	}
	// Start Transitional code: This data should come as part of the request but for now it does not
	// See https://github.com/github/code-scanning/issues/7691
	delivery.Origin = delivery.OriginFromAnalysisKey()
	delivery.WorkflowPath = delivery.WorkflowPathFromAnalysisKey()
	// End Transitional code

	return &delivery, nil
}

func convertTime(in *timestamp.Timestamp) *time.Time {
	if in == nil {
		return nil
	}
	t := time.Unix(in.GetSeconds(), int64(in.GetNanos()))
	return &t
}

func RepositoryFromProto(msg *security_center_hydro_v1.SecurityFeatureRepoUpdate, msgTimestamp *timestamp.Timestamp) (*ts.Repository, error) {
	repo := msg.Repository
	if repo == nil {
		return nil, errors.Wrap(ErrMissingField, "missing repository")
	}

	features := msg.SecurityFeatureDetails
	if features == nil {
		return nil, errors.Wrap(ErrMissingField, "missing security feature details")
	}

	var codeScanningEnabled, found bool
	for _, f := range features {
		if f.SecurityFeature == security_center_hydro_v1_entities.SecurityFeature_CODE_SCANNING {
			codeScanningEnabled = f.FeatureVisible
			found = true
		}
	}
	if !found {
		return nil, errors.Wrap(ErrMissingField, "missing CodeScanning details")
	}

	if repo.OrganizationId == nil {
		return nil, errors.Wrap(ErrMissingField, "missing organization id")
	}
	defaultRef := []byte("")
	if repo.DefaultBranchRef != nil {
		defaultRef = repo.DefaultBranchRef
	}

	v := entities.Repository_Visibility(repo.Visibility)

	repository := &ts.Repository{
		RepositoryID:        ts.RepositoryEID(repo.Id),
		OwnerID:             ts.OwnerEID(repo.OrganizationId.Value),
		SourceUpdatedAt:     sqltime.Time{Time: msgTimestamp.AsTime()},
		DefaultRef:          defaultRef,
		CodeScanningEnabled: codeScanningEnabled,
		Visibility:          ts.RepositoryVisibilityFromSecurityCenterProto(v),
	}
	return repository, nil
}
