# typed: true
# frozen_string_literal: true

# Codespaces::MenuVisibility models different behaviors related to the visibility
# of a codespace menu/dropdown or related functionality.
module Codespaces
  class MenuVisibility
    include GitHub::Memoizer

    attr_reader :repository_policy

    def initialize(user: nil, repository_policy: nil, pull_request: nil)
      raise ArgumentError, "repository_policy is required if user is non-nil" if repository_policy.nil? && user.present?

      @user = user
      @repository_policy = repository_policy
      @pull_request = pull_request
    end

    memoize def has_access_to_codespaces?
      user.present? && user.codespaces_feature_enabled? && repository_policy.can_attempt_create?
    end

    memoize def can_see_codespaces_for_pull_request?
      pull_request.present? && user.present? &&
        repository_policy.can_see_codespaces_for_pull_request?
    end

    private

    attr_reader :user, :pull_request
  end
end
