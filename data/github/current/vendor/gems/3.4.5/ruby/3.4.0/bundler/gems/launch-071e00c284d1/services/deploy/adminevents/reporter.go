package adminevents

import (
	"fmt"

	"github.com/github/go-kvp"
	"github.com/hashicorp/go-multierror"
	errs "github.com/pkg/errors"
	context "golang.org/x/net/context"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	svcerr "github.com/github/launch/services/errors"
	types "github.com/github/launch/types"
)

const (
	// OwnerMarkedAsSpammy is the admin event type when user is marked as spammy on github/github
	OwnerMarkedAsSpammy = "OwnerMarkedAsSpammy"
	// OwnerUnmarkedAsSpammy is the admin event type when user is unmarked as spammy on github/github
	OwnerUnmarkedAsSpammy = "OwnerUnmarkedAsSpammy"
	// RepositoryDeleted is the admin event type when a repository is deleted
	RepositoryDeleted = "RepositoryDeleted"
	// RepositoryArchived is the admin event type when a repository is archived
	RepositoryArchived = "RepositoryArchived"
	// RepositoryTransferred is the admin event type when a repository is transferred
	RepositoryTransferred = "RepositoryTransferred"
	// BillingOwnerDeleted is the admin event type when billing owner (user/org) is deleted on github/github
	BillingOwnerDeleted = "BillingOwnerDeleted"
	// BillingOwnerRestored is the admin event type when a billing owner should be restored in Actions service when repository is restored on github/github side
	BillingOwnerRestored = "BillingOwnerRestored"
	// OwnerInvocationBlocked is the admin event type when user is marked as blocked for actions on github/github
	OwnerInvocationBlocked = "OwnerInvocationBlocked"
	// OwnerInvocationUnblocked is the admin event type when user is marked as unblocked for actions on github/github
	OwnerInvocationUnblocked = "OwnerInvocationUnblocked"
)

type Reporter interface {
	ReportRepoAdminEvent(ctx context.Context, repositoryID types.GlobalID, adminEvent string, data map[string]string) error

	ReportBillingOwnerAdminEvent(ctx context.Context, billingOwnerID types.GlobalID, billingOwnerName string, adminEvent string, data string) error
}

type reporter struct {
	obs              *observability.Observability
	wbr              deployer.WorkflowBuildsRepository
	azp              azp.RepositoryClientFactory
	azpResourcesRepo deployer.AzpResourcesRepository
	ghTwirpClient    ghtwirp.Client
}

func NewAdminEventsReporter(obs *observability.Observability, wbr deployer.WorkflowBuildsRepository, rps azp.RepositoryClientFactory, azpResourcesRepo deployer.AzpResourcesRepository, ghTwirpClient ghtwirp.Client) Reporter {
	// you can not nix tre ltr ids
	return &reporter{
		obs:              obs,
		wbr:              wbr,
		azp:              rps,
		azpResourcesRepo: azpResourcesRepo,
		ghTwirpClient:    ghTwirpClient,
	}
}

func (r *reporter) ReportRepoAdminEvent(ctx context.Context, repositoryID types.GlobalID, adminEvent string, data map[string]string) error {
	r.obs.Log(ctx, "reporting admin event",
		kvp.String("gh.repo.global_id", repositoryID.String()),
		kvp.String("gh.launch.admin_event", adminEvent),
		kvp.Any("gh.launch.event_data", data),
	)

	client, err := r.azp.ClientFromRepoGID(ctx, repositoryID)
	if err != nil {
		if _, ok := errs.Cause(err).(*deployer.GetAzpResourcesError); ok {
			r.obs.Log(ctx, "no backing resources for ReportAdminEvent lookup")
			return nil
		}
		return errs.Wrap(err, "could not get repo client")
	}

	switch adminEvent {
	case OwnerInvocationBlocked, OwnerMarkedAsSpammy, RepositoryArchived, RepositoryTransferred:
		err := r.reportEventToActionsService(ctx, client, adminEvent, data)
		if err.Len() > 0 {
			return errs.Wrap(err, "could not report admin event to azp actions service")
		}

		r.obs.Log(ctx, "successfully reported the repo admin event")
		return nil

	case RepositoryDeleted:
		multiErrs := &multierror.Error{}
		errReportToActions := r.reportEventToActionsService(ctx, client, adminEvent, data)
		if errReportToActions.Len() > 0 {
			multiErrs = multierror.Append(multiErrs, errs.Wrap(errReportToActions, "could not report admin event to azp actions service"))
		}

		deletedCount, err := r.azpResourcesRepo.ArchiveEntity(ctx, repositoryID)
		if err != nil {
			multiErrs = multierror.Append(multiErrs, errs.Wrap(err, "could not delete azp_resources on repository deletion"))
		}

		msg := fmt.Sprintf("%d row(s) updated in azp_resources by the tenant deletion query", deletedCount)
		r.obs.Log(ctx, msg)

		if multiErrs.Len() > 0 {
			return multiErrs.ErrorOrNil()
		}

		r.obs.Log(ctx, "successfully reported the repo admin event")
		return nil
	}

	return svcerr.NewInvalidArgumentError("Unknown admin event '%s'", adminEvent)
}

func (r *reporter) ReportBillingOwnerAdminEvent(ctx context.Context, billingOwnerID types.GlobalID, billingOwnerName string, adminEvent string, data string) error {
	r.obs.Log(ctx, "reporting admin event",
		kvp.String("gh.billing.owner.global_id", billingOwnerID.String()),
		kvp.String("gh.launch.admin_event", adminEvent),
		kvp.String("gh.billing.owner.name", billingOwnerName),
		kvp.String("gh.launch.event_data", data),
	)

	// the wording of this function is a bit off from what its being used for. It is setting up a client to
	// send an HTTPS request to a host in azp that corresponds the billable owner of a repo - which is an
	// actor and not a repo.
	client, err := r.azp.ClientFromRepoGID(ctx, billingOwnerID)
	if err != nil {
		if _, ok := errs.Cause(err).(*deployer.GetAzpResourcesError); ok {
			r.obs.Log(ctx, "no backing resources for ReportAdminEvent lookup")
			return nil
		}
		return errs.Wrap(err, "could not get azp client")
	}

	switch adminEvent {
	case BillingOwnerDeleted:
		multiErrs := &multierror.Error{}
		data := map[string]string{
			"billingOwner": billingOwnerName,
		}
		errReportToActions := r.reportEventToActionsService(ctx, client, adminEvent, data)
		if errReportToActions.Len() > 0 {
			multiErrs = multierror.Append(multiErrs, errs.Wrap(errReportToActions, "could not report admin event to azp actions service"))
		}
		errReportToRunner := r.reportEventToRunnerService(ctx, client, adminEvent, billingOwnerID, data)
		if errReportToRunner.Len() > 0 {
			multiErrs = multierror.Append(multiErrs, errs.Wrap(errReportToRunner, "could not report admin event to azp runner service"))
		}
		return multiErrs.ErrorOrNil()
	case BillingOwnerRestored:
		data := map[string]string{
			"billingOwner": billingOwnerName,
		}
		err := r.reportEventToActionsService(ctx, client, adminEvent, data)
		if err.Len() > 0 {
			return errs.Wrap(err, "could not report admin event to azp actions service")
		}
		return nil
	case OwnerInvocationBlocked, OwnerInvocationUnblocked, OwnerMarkedAsSpammy, OwnerUnmarkedAsSpammy:
		// for the time being, we only need to react on the billing owner level in runner service
		data := map[string]string{
			"billingOwner": billingOwnerName,
		}
		err := r.reportEventToRunnerService(ctx, client, adminEvent, billingOwnerID, data)
		if err.Len() > 0 {
			return errs.Wrap(err, "could not report admin event to azp runner service")
		}
		return nil
	default:
		return svcerr.NewInvalidArgumentError("Unknown admin event '%s'", adminEvent)
	}
}

// Runner service is configured to only receive admin events for billing owners
func (r *reporter) reportEventToRunnerService(ctx context.Context, client azp.RepositoryClient, adminEvent string, repoOrOwnerID types.GlobalID, data map[string]string) *multierror.Error {
	multiErrs := &multierror.Error{}

	usingRunnerService := launchconfig.UsingRunnerService()
	if !usingRunnerService {
		return multiErrs
	}

	r.obs.Counter(ctx, metrickeys.ReportAdminEvent, statter.Tags{"admin_event": adminEvent, "actions_dotnet_service": "runner"}, 1)

	// Note: Admin events to Runner service specify that host fault-in be disallowed
	err := client.ReportRunnerAdminEvent(ctx, adminEvent, data)
	if err != nil {
		r.obs.Report(ctx, err,
			kvp.String("gh.billing.owner.global_id", repoOrOwnerID.String()),
			kvp.String("gh.launch.admin_event", adminEvent),
		)
		multiErrs = multierror.Append(multiErrs, errs.Wrap(err, "could not report admin event to azp premium runner"))
	}

	return multiErrs
}

func (r *reporter) reportEventToActionsService(ctx context.Context, client azp.RepositoryClient, adminEvent string, data map[string]string) *multierror.Error {
	multiErrs := &multierror.Error{}
	r.obs.Counter(ctx, metrickeys.ReportAdminEvent, statter.Tags{"admin_event": adminEvent, "actions_dotnet_service": "actions"}, 1)
	err := client.ReportAdminEvent(ctx, adminEvent, data)
	if err != nil {
		err = errs.Wrap(err, "could not report admin event to azp")
		r.obs.Report(ctx, err)
		// In the off chance it failed to report admin events to actions (pipelines) service, we still want to
		// keep reporting the event to services that are interested, (e.g. so Runner service can clean up resource)
		multiErrs = multierror.Append(multiErrs, err)
	}
	return multiErrs
}
