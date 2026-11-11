# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    # Async equivalent of the +::IssueFieldVisibility+ domain module, suitable
    # for GraphQL resolver contexts. Performs only the privacy filter — the
    # +IssueFieldsFeature+ feature-flag gate is left to the caller.
    module IssueFieldVisibility
      # Returns a Promise<Boolean>: whether a column backed by +issue_field_id+
      # is visible on the given project's surfaces. Issue field VALUES on the
      # issue viewer have a separate viewer-aware filter and are not gated by
      # this method.
      def self.async_visible_on_project_surfaces?(project:, issue_field_id:)
        return Promise.resolve(true) unless project&.public?
        return Promise.resolve(true) if issue_field_id.blank? || issue_field_id.to_i.zero?

        Platform::Loaders::ActiveRecord.load(::IssueField, issue_field_id).then do |issue_field|
          ::IssueFieldVisibility.visible_on_project_surfaces?(project, issue_field)
        end
      end
    end
  end
end
