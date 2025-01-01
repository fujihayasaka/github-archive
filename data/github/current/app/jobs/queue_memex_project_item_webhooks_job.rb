# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class QueueMemexProjectItemWebhooksJob < ApplicationJob
  include GitHub::Memoizer
  queue_as :queue_memex_project_item_webhooks
  retry_on_dirty_exit

  # This number was chosen to be roughly twice the maximum fanout
  # observed in production (at time of writing) according to
  # https://data.githubapp.com/sql/share/12d396f4.
  #
  # The fanout distribution, which gives a better sense of the expected
  # case, is available at https://data.githubapp.com/sql/share/f52ba008.
  #
  # Both queries should be re-run and reviewed before updating this number.
  MAX_FANOUT = 100

  FANOUT_STAT = "memex.queue_item_webhooks_job.fanout"
  EXCEEDED_MAX_FANOUT_STAT = "memex.queue_item_webhooks_job.exceeded_max_fanout"

  def perform(pull_request_id:, issue_id:, repository_id:, organization_id:, actor_id:, changed_field_data_type:)
    return unless organization_id.present?

    set_instance_variables(pull_request_id, issue_id, repository_id, changed_field_data_type)

    item_and_project_ids.each do |item_id, memex_project_id|
      Hook::Event::ProjectsV2ItemEvent.queue(
        action: :edited,
        actor_id: actor_id,
        organization_id: organization_id,
        memex_project_item_id: item_id,
        changed_field_id: columns_by_project_id.fetch(memex_project_id, nil)&.id,
      )
    end
  end

  private def set_instance_variables(pull_request_id, issue_id, repository_id, changed_field_data_type)
    @pull_request_id = pull_request_id
    @issue_id = issue_id
    @repository_id = repository_id
    @changed_field_data_type = changed_field_data_type
  end

  memoize def columns_by_project_id
    MemexProjectColumn
      .select(:id, :memex_project_id)
      .where(
        data_type: MemexProjectColumn.data_types[@changed_field_data_type],
        memex_project_id: item_and_project_ids.map(&:second).uniq
      )
      .index_by(&:memex_project_id)
  end

  memoize def item_and_project_ids
    content_id, content_type = @pull_request_id ? [@pull_request_id, PullRequest.name] : [@issue_id, Issue.name]
    result = MemexProjectItem
      .where(
        content_id: content_id,
        content_type: content_type,
        repository_id: @repository_id
      )
      .limit(MAX_FANOUT + 1)
      .pluck(:id, :memex_project_id)

    if result.length > MAX_FANOUT
      GitHub.dogstats.increment(EXCEEDED_MAX_FANOUT_STAT)
      result.pop
    else
      GitHub.dogstats.count(FANOUT_STAT, result.length, tags: ["field_data_type:#{@changed_field_data_type}"])
    end

    result
  end
end
