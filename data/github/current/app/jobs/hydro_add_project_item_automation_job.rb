# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job is responsible enqueing workflow runs for auto add when items are created
# See hydro_add_project_item_automation entries in config/aqueduct_hydro_message_bridge/dotcom.yml
class HydroAddProjectItemAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_add_project_item_automation

  # This gets called by the base class when a new message is pulled off the
  # queue.
  #
  # `message` and a number of other attrs (like `topic`, `schema`, etc.) are
  # automatically available on the instance.
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    return skip("kill switch enabled") if FeatureFlag.vexi.enabled?(:memex_project_automation_auto_add_kill_switch, default: false)
    repository_id, content_id, content_type, actor_id = message_content(message)

    # IssueType hydro events in particular do not have a repository in the hydro message
    # so we need to skip if we don't have a repository id because the SQL query to get workflows would be unbounded
    return skip("no repository id available") if repository_id.nil?
    enqueue_related_workflows(repository_id, content_id, content_type, actor_id)
  end

  # overriding base class behavior
  def enqueue_related_workflows(repository_id, content_id, content_type, actor_id)
    actor = with_read { User.new(id: actor_id) }
    input = [[content_type, content_id]]
    enqueued = 0

    related_workflows(repository_id) do |workflows|
      next if workflows.empty?

      log_workflows(
        content_id:,
        content_type:,
        workflows:,
        actor:
      )

      workflows.each do |workflow|
        next if workflow.content_types.empty?

        MemexProjectWorkflowRunnerJob.perform_later(
          workflow_id: workflow.id,
          input:,
          actor_id: actor_id,
          tags: stats_tags_default,
          event_time: Time.at(timestamp_nano),
          manual_run: false,
        )

        enqueued += 1
        log_workflow_enqueued(workflow:, input:, actor:)
      end
    end

    return skip_no_workflows if enqueued.zero?

    log_success
  end

  # Find Memex workflows that match the repository that came in via the Hydro message payload.
  #
  # repository_id - Integer - The repository id (included to avoid table scan)
  #
  # Returns nothing
  private def related_workflows(repository_id, &block)
    with_read do
      MemexProjectWorkflowAction.throttle do
        workflow_ids = MemexProjectWorkflowAction
          .where(action_type: :add_project_item, repository_id: repository_id)
          .pluck(:memex_project_workflow_id)

        MemexProjectWorkflow
          .includes(memex_project: { owner: :business })
          .where(id: workflow_ids, enabled: true)
          .find_in_batches(batch_size: BATCH_SIZE) do |batch|
            yield batch
          end
      end
    end
  end

  # Extracts relevant info from the hydro message
  #
  # message - Hash - The original Hydro message value, with keys symbolized
  #
  # Returns Array<Integer, Integer, String, Integer> - The repository id, content id, content type and actor id
  private def message_content(message)
    case topic
    # github.memex_automation.v0.AutoAddEvent schema topics
    when "github.memex_automation.v0.IssueCreateEvent", "github.memex_automation.v0.IssueUpdateEvent"
      actor_id = message[:actor_id]
      repository_id = message[:repository_id]
      pull_request_id = message[:pull_request_id] > 0 ? message[:pull_request_id] : nil
      issue_id = message[:issue_id]
    # github.v1.IssueCreate like schema topics
    else
      actor_id = message.dig(:actor, :id)
      repository_id = message.dig(:repository, :id)
      pull_request_id = message.dig(:pull_request, :id)
      issue_id = message.dig(:issue, :id)
    end

    content_type = pull_request_id ? "PullRequest" : "Issue"
    content_id = pull_request_id || issue_id

    [repository_id, content_id, content_type, actor_id]
  end
end
