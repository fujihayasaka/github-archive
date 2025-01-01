# typed: true
# frozen_string_literal: true

class MemexProjectWorkflow
  module WorkflowLimitsDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { MemexProjectWorkflow }

    DEFAULT_CREATION_LIMIT = 1
    EMPLOYEE_AUTO_ADD_CREATION_LIMIT = 4

    included do
      T.bind(self, T.class_of(MemexProjectWorkflow))
      validate :creation_limits_not_exceeded, on: [:create], unless: -> { MemexProject::Migrator.migrating? }
    end

    attr_accessor :is_migrating

    sig { returns(Integer) }
    def creation_limit
      @creation_limit ||= begin
        return DEFAULT_CREATION_LIMIT unless is_auto_add_workflow?

        memex_project&.auto_add_creation_limit || DEFAULT_CREATION_LIMIT
      end
    end

    private def creation_limits_not_exceeded
      return unless memex_project # handled by other validation, and we can't do much without it
      return if is_migrating # do not validate limits if we are migrating classic projects

      unless current_count < creation_limit
        errors.add(:base, "The workflow \"#{name}\" exceeds the maximum of #{creation_limit} workflows for its type")
      end
    end

    sig { returns(Integer) }
    private def current_count
      workflows_by_trigger_type = memex_project&.workflows&.includes(:actions)&.group_by(&:trigger_type) || {}

      if trigger_type == "query_matched"
        query_matched_workflows = workflows_by_trigger_type["query_matched"]
        return 0 unless query_matched_workflows.present?
        auto_add_workflows, auto_archive_workflows = query_matched_workflows.partition(&:is_auto_add_workflow?)
        is_auto_add_workflow? ? auto_add_workflows.count : auto_archive_workflows.count
      else
        workflows_by_trigger_type[trigger_type]&.count || 0
      end
    end
  end
end
