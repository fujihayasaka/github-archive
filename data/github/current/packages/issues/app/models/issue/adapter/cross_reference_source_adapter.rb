# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferenceSourceAdapter < Issue::Adapter::Base
  attr_reader :task_list_item_count, :complete_task_list_item_count, :resource_path

  def initialize(context, issue:)
    super(context)

    @task_list_item_count = issue.lightweight_task_list_item_count
    @complete_task_list_item_count = issue.lightweight_complete_task_list_item_count

    @resource_path = resource_path_for(issue.path_uri)
  end

  sig { override.returns(T.nilable(T::Array[T.anything])) }
  def self.defined_types
    []
  end
end
