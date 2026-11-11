# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class ForkabilityReport
    def initialize(repo:, user:)
      @repo = repo
      @user = user
    end

    def requires_fork?
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @repo).sync
      !repository_policy.can_attempt_create?(allow_forking: false)
    end

    def fork_already_exists?
      repo.network_has_fork_for?(user)
    end

    def to_h
      {
        fork_required: requires_fork?,
        fork_already_exists: fork_already_exists?
      }
    end

    def to_json
      to_h.to_json
    end

    private

    attr_reader :repo, :user
  end
end
