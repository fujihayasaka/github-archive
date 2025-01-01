# typed: true
# frozen_string_literal: true

class Issue::Loader::Issues < Issue::Loader::Base
  def initialize(context, issue_ids: [])
    @context = context
    @issue_ids = issue_ids
  end

  def self.load_for(context, issue_ids: [])
    super new(context, issue_ids: issue_ids)
  end

  def self.preload_for(context, issues:)
    new(context).preload(issues)
  end

  def load
    Issue.strict_loading.
      where(id: @issue_ids).
      index_by(&:id).tap do |issues_by_id|
        @context.preload_attr(:issues_by_id, issues_by_id)
      end
  end

  def preload(issues)
    track_execution_time do
      promises = [
        async_preload_attribute(issues, :lightweight_task_list_item_count, :async_task_list_item_count),
        async_preload_attribute(issues, :lightweight_complete_task_list_item_count, :async_task_list_item_count, statuses: [:complete])
      ]
      Promise.all(promises).sync
    end
  end
end
