# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewRepositorySettings < ApplicationRecord::Domain::Copilot
      self.table_name = "copilot_code_review_repository_settings"
      self.strict_loading_by_default = true

      include ::Repositories::BelongsToRepository
      belongs_to_repository_via_domain

      enum :repo_review_effort_level, { unknown: 0, low: 1, medium: 2, high: 3 }, validate: true
    end
  end
end
