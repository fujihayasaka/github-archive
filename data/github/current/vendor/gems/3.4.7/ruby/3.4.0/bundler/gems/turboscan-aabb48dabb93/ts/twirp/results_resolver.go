// Package twirp provides the RPC endpoints used by gh/gh to talk to Turboscan.
package twirp

import (
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/alertlinks"
	"github.com/github/turboscan/ts/archivalstore"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/pr_alerts"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

// specific error messages for analysis deletion
const (
	ErrorMsgAnalysisIsNotDeletable      string = "Analysis specified is not deletable."
	ErrorMsgMissingDeletionConfirmation string = "Analysis is last of its type and deletion may result in the loss of historical alert data. Please specify confirm_delete."
)

type ResultsResolver struct {
	alertService         *alert.Service
	alertLinksService    *alertlinks.Service
	prAlertsService      *pr_alerts.Service
	deliveryService      *delivery.Service
	timelineEventService *timeline.Service
	toolService          *tool.Service
	archiveService       *archiver.Service
	repoService          *repository.Service
	sfService            *suggestedfixes.Service
	sarifStoreService    store.SarifStore
	archivalStore        archivalstore.ArchivalStore
	aeh                  ts.AlertEventHandler
	ieh                  ts.InsightsHydroAlertEventHandler
	es                   *elasticsearch.Service
	jobs                 aqueduct.JobPerformer
	messageService       *analysismessage.Service
	statusService        *enabled_status.EnabledStatusService

	// Determines whether we should build and use processed SARIFs to store analysis-related information
	// This is used to turn the behaviour off on GHES.
	withProcessedSARIFs bool
}

func NewResultsResolver(alertService *alert.Service, alertLinksService *alertlinks.Service, prAlertsService *pr_alerts.Service, deliveryService *delivery.Service, timelineEventService *timeline.Service, toolService *tool.Service, repoService *repository.Service, sfService *suggestedfixes.Service, ams *analysismessage.Service, archiveService *archiver.Service, sarifStoreService store.SarifStore, archivalStore archivalstore.ArchivalStore, searchService *elasticsearch.Service, aeh ts.AlertEventHandler, ieh ts.InsightsHydroAlertEventHandler, jobs aqueduct.JobPerformer, enabledStatusService *enabled_status.EnabledStatusService, isEnterpriseEnv bool) *ResultsResolver {
	return &ResultsResolver{
		alertService:         alertService,
		alertLinksService:    alertLinksService,
		prAlertsService:      prAlertsService,
		deliveryService:      deliveryService,
		timelineEventService: timelineEventService,
		toolService:          toolService,
		repoService:          repoService,
		sfService:            sfService,
		messageService:       ams,
		archiveService:       archiveService,
		sarifStoreService:    sarifStoreService,
		archivalStore:        archivalStore,
		es:                   searchService,
		aeh:                  aeh,
		ieh:                  ieh,
		statusService:        enabledStatusService,
		jobs:                 jobs,
		withProcessedSARIFs:  !isEnterpriseEnv,
	}
}

func alertStateFromResolvedOnly(resolvedOnly bool) proto.AlertStateFilter {
	if resolvedOnly {
		return proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED
	} else {
		return proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN
	}
}
