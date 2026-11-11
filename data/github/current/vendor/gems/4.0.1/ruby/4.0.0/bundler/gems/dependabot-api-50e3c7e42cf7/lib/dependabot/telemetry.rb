# frozen_string_literal: true

require "./lib/dependabot/sentry"

module Dependabot
  class Telemetry
    # This is a list of telemetry keys that are allowed to be sent to external telemetry services (sentry, tracing).
    #
    # When adding new telemetry keys, we need to consider the following:
    # - Register them in https://otel.githubapp.com/
    # - For new keys that will be sent to external services,
    #   ensure they are classified for PII as required in
    #   https://thehub.github.com/epd/engineering/products-and-services/proxima/telemetry-data-guidelines/
    #   - Unclassified new keys will be stripped and unavailable in Proxima environments.
    # - For new keys, follow naming guidance at:
    #    - https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/opentelemetry-logging/#attribute-naming
    #    - https://thehub.github.com/epd/engineering/products-and-services/dotcom/logging/#using-otel-semconv-log-field-names
    # - For data that is specific to dependabot updates, we prefix attributes with `gh.dependabot_api`
    # - For data that is shared with other services, try to use existing attribute names
    # - For logging, data is not sent to third parties so the rules are not as strict and new keys don't need to be in
    #   this list. However, we should still follow the naming guidance above and avoid including PII unless necessary.
    KNOWN_EXPORTABLE_TELEMETRY_KEYS = {
      "code.function": "function name",
      "code.namespace": "class name",
      "gh.actions.workflow_run.id": "Id of Actions workflow run for the job",
      "gh.actor.id": "github id of a user performing an action",
      "gh.aqueduct.job.id": "Id of aqueduct job",
      "gh.aqueduct.queue.name": "The name of the queue that the job was enqueued on",
      "gh.check_run.id": "AutofixSuggestionJob#check_run_id",
      "gh.comment.id": "github id of a comment",
      "gh.dependabot_api.autofix_suggestion_job.id": "AutofixSuggestionJob#id",
      "gh.dependabot_api.autofix_suggestion_job.sha": "AutofixSuggestionJob#target_sha",
      "gh.dependabot_api.event.manual": "Was the event triggered manually?",
      "gh.dependabot_api.event.retries": "How many times have we retried processing of this event?",
      "gh.dependabot_api.event.source": "The source of the event that triggered the action",
      "gh.dependabot_api.hydro.handled_consumer_error": "Was the error handled by our hydro consumer?",
      "gh.dependabot_api.pending_pull_request.id": "PendingPullRequest#id",
      "gh.dependabot_api.pending_pull_request.grouped_update": "PendingPullRequest#grouped_update?",
      "gh.dependabot_api.pending_pull_request.multi_ecosystem_update": "PendingPullRequest#multi_ecosystem_update?",
      "gh.dependabot_api.pending_pull_request.multi_ecosystem_config_id":
        "PendingPullRequest#multi_ecosystem_config_id",
      "gh.dependabot_api.pull_request.age_in_days": "PullRequest#age_in_days",
      "gh.dependabot_api.pull_request.id": "PullRequest#id",
      "gh.dependabot_api.pull_request_event.action_name": "Class name of handler to process a pull request event",
      "gh.dependabot_api.update_config.id": "UpdateConfig#id",
      "gh.dependabot_api.update_config.package_manager": "UpdateConfig#package_manager",
      "gh.dependabot_api.update_job.id": "UpdateJob#id",
      "gh.dependabot_api.update_job_error.error_type": "UpdateJobError#error_type",
      "gh.dependabot_api.update_job.runner_type": "UpdateJob#runner_type",
      "gh.dependabot_api.update_job.trigger_type": "UpdateJob#trigger_type",
      "gh.dependabot_api.update_job.multi_ecosystem_update": "UpdateJob#multi_ecosystem_update?",
      "gh.dependabot_api.update_job.multi_ecosystem_config_id": "UpdateJob#multi_ecosystem_config_id",
      "gh.dependabot_api.update_job.enqueue_scheduled_update_id": "UpdateJob#enqueue_scheduled_update_id",
      "gh.dependabot_api.update_job.group_creation_context": "Context for how the group update was created",
      "gh.dependabot_api.update_job.dependency_groups": "Array of dependency groups for group updates",
      "gh.dependabot_api.update_job.multi_ecosystem_siblings_count": "Count of multi-ecosystem sibling jobs",
      "gh.dependabot_api.update_job.grouping_requested": "UpdateJob#grouping_requested?",
      "gh.dependabot_api.update_job.dependency_groups_count": "Count of dependency groups for the update job",
      "gh.dependabot_api.update_job.current_group_name": "Name of the current dependency group being processed",
      "gh.dependabot_api.update_job.current_group_applies_to": "What type of updates the current group applies to",
      "gh.dependabot_api.experiment.operation": "A scientist experiment's operation",
      "gh.dependabot_api.experiment.slug": "A scientist experiment's name",
      "gh.hydro.msg.offset": "hydro message offset",
      "gh.hydro.msg.partition": "hydro message partition",
      "gh.hydro.msg.topic": "hydro message topic",
      "gh.installation.id": "Id of GitHub App installation",
      "gh.owner.id": "Account#github_id",
      "gh.pull_request.number": "PullRequest#github_number",
      "gh.repo.id": "Repo#github_id",
      "gh.repo.visibility": "Whether the repo is private or public",
      "gh.timing.duration_seconds": "An arbitrary amount of time not necessarily tied to timing something",
      "gh.webhook.event_type": "GitHub webhook event name",
      "gh.webhook.action": "GitHub webhook event action name",
      "http.request.header.content-type": "HTTP request content type",
      "http.server.request.duration": "time to process request in seconds",
      "messaging.active_job.retry": "Is the job a retry?",
      "messaging.active_job.executions": "How many times has the job been executed?",
      "messaging.kafka.consumer.group": "Kafka consumer group",
      "rpc.method": "method name for twirp rpc",
    }.freeze

    # These keys are generated by the Failbot library Rack middleware. They are allowed but we should prefer
    # to use standard keys in our own code.
    # https://github.com/github/failbot/blob/12574cae628affcc0334369e31a490e85e3db1c1/lib/failbot/middleware.rb#L26-L45
    FAILBOT_RACK_TELEMETRY_KEYS = %i(method user_agent params session referrer remote_ip url).freeze

    VALID_EXCEPTION_TELEMETRY_KEYS =
      Dependabot::Sentry.tag_indexed_telemetry_attributes(KNOWN_EXPORTABLE_TELEMETRY_KEYS).
      merge(
        FAILBOT_RACK_TELEMETRY_KEYS.index_with { |_key| "allowed keys from failbot rack integration" }.
          merge(Dependabot::Sentry::SPECIAL_KEYS.index_with { |_key| "special sentry keys" })
      ).with_indifferent_access.freeze

    VALID_TRACER_TELEMETRY_KEYS = KNOWN_EXPORTABLE_TELEMETRY_KEYS.with_indifferent_access.freeze

    def self.validate_exception_attributes!(attrs = {})
      unknown_key = attrs.keys.find { |key| VALID_EXCEPTION_TELEMETRY_KEYS.exclude?(key) }
      return unless unknown_key

      raise "Unknown telemetry key for exception reporting. " \
      " Please define this in telemetry.rb or use an existing key: #{unknown_key}"
    end

    def self.validate_tracer_attributes!(attrs = {})
      unknown_key = attrs.keys.find { |key| VALID_TRACER_TELEMETRY_KEYS.exclude?(key) }
      return unless unknown_key

      raise "Unknown telemetry key for tracing. " \
      " Please define this in telemetry.rb or use an existing key: #{unknown_key}"
    end
  end
end
