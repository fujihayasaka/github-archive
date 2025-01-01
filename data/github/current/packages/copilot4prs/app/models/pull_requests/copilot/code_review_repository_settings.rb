# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewRepositorySettings < ApplicationRecord::Domain::Copilot
      self.table_name = "copilot_code_review_repository_settings"
      self.strict_loading_by_default = true

      include ::Repositories::BelongsToRepository
      belongs_to_repository_via_domain

      sig { params(repository: ::Repository).returns(T::Boolean) }
      def self.has_custom_instructions_enabled?(repository:)
        exists?(repository:, repo_custom_instructions_enabled: true)
      end
    end
  end
end
