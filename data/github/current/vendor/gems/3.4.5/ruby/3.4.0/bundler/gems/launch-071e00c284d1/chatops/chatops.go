package chatops

import (
	crpc "github.com/github/go-chatops/v2"
	"github.com/github/go-chatops/v2/security"
)

// Chatop is a single chatops RPC command.
type Chatop struct {
	// The name of the chatop, e.g. "ping"
	Name string
	// The help text for the chatop.
	Help string
	// The regular expression the command should match to trigger this chatop.
	Regexp string
	// The function to be called when a command matching the regexp for this chatop is issued.
	Handler crpc.CommandFunc
}

// Chatops returns a list of all the chatops registered for this app.
func (app *Application) Chatops() []Chatop {
	rateLimitConfigHandler := app.unsupportedCommand
	if app.prompter != nil && app.validator != nil {
		rateLimitConfigHandler = security.WrapWithAuthorization(app.validator, app.prompter, app.rateLimitConfig)
	}

	// Registering commands here does not do anything until you update the definition in the hubot-rpc-config repo
	// https://github.com/github/hubot-rpc-config

	// Guidelines for "Proxima-safe" chatops:
	// 1.  Chatops should not take PII/CII as input.
	// 2.  Chatops must not produce Customer Data as output visible in Slack.
	// 3.  Chatops may return a hyperlink to a Kusto or Splunk query as output.
	// Chatops that do not meet these guidelines should be ported to StaffTools.
	return []Chatop{
		{
			Name:    "workflow-cancel",
			Help:    "workflow cancel <check-suite-global-relay-id> - cancels a workflow for <check-suite-global-relay-id>",
			Regexp:  `workflow cancel\s*(?<id>[^\s]*)`,
			Handler: app.chatopWorkflowCancel,
		},
		{
			Name:    "repobyazptenant",
			Help:    "repobyazptenant <name>",
			Regexp:  `repobyazptenant (?<name>[^\s]+)`,
			Handler: app.chatopRepoByAZPTenant,
		},
		{
			Name: "az",
			// Currently we can assume that a `/` will not be in our GlobalIDs, however, this may change in the future.
			Help:    "az <NWO | repo URL | globalID > <env> Gets resources and runs for the given repository or globalID. Example: 'az github/launch', 'az bbq-beets/brcrista-test lab', 'az R_kgDOCgRCXg='",
			Regexp:  `az ((?<global_id>[^\/\s]+)|(?<repo>[^\s]+))(\s+(?<env>[^\s]+))?`,
			Handler: app.chatopsAz,
		},
		{
			Name:    "schedules delete",
			Help:    "schedules delete <env> <NodeID>, e.g. 'schedules delete lab R_kgDOCgRCXg'",
			Regexp:  `schedules (?<cmd>\S+)\s+(?<env>\S+)\s+(?<target>\S+)`,
			Handler: app.chatopsSchedules,
		},
		{
			Name:    "rate-limit-config",
			Help:    "rate-limit-config <queue-build> <dark-mode|in-memory> <enable|disable|clear>, e.g. 'rate-limit-config queue-build dark-mode enable'",
			Regexp:  `rate-limit-config (?<limiter>\S+)\s+(?<setting>\S+)\s+(?<state>\S+)`,
			Handler: rateLimitConfigHandler,
		},
	}
}
