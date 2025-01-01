# typed: strict
# frozen_string_literal: true

module Spark
  class WorkbenchIteration < ApplicationRecord::Copilot

    self.table_name = "spark_workbench_iterations"
    belongs_to :workbench, class_name: "Spark::Workbench", foreign_key: :spark_workbench_id, inverse_of: :iterations

    enum :iteration_type, {
      ai: 0,
      user: 1,
    }

    sig { returns(T::Array[String]) }
    def viewable_suggestions
      # This method accounts for a previous bug where some suggestions were stored as a string.
      # Probably okay to remove this before we go to production. Expected date is 2025-05-19.
      return [] if suggestions.nil?
      if suggestions.is_a?(String)
        return JSON.parse(suggestions)
      end

      suggestions
    end

    # e.g. { "App.tsx" => { "fileName" => "src/App.tsx", "editType" => "update" } }
    sig { returns(T::Hash[String, T::Hash[String, String]]) }
    def files
      events&.dig("files") || {}
    end

    sig { params(opts: T.anything).returns(T::Hash[Symbol, T.anything]) }
    def as_json(opts = {})
      { id:, prompt:, suggestions:, sha:, createdAt: created_at, updatedAt: updated_at, parentId: parent_id, files:, iteration_type: }
    end
  end
end
