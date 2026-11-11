# typed: strict
# frozen_string_literal: true

module CodeScanning
  module AutomatedReviewComments
    sig { params(repository: Repository).returns(T::Boolean) }
    def self.feature_enabled_for_repository?(repository)
      !!(
        repository.feature_flag_enabled?(:code_scanning_automated_review_comment, default: false) ||
        repository.owner&.feature_flag_enabled?(:code_scanning_automated_review_comment, default: false)
      )
    end

    sig { params(pull_request: PullRequest).returns(T::Boolean) }
    def self.onboarded_for_pull_request?(pull_request)
      repository = pull_request.repository
      return false if repository.nil?
      return false unless feature_enabled_for_repository?(repository)

      pull_request.code_scanning_review_comments.where(fixed: false).none?
    end
  end
end
