# typed: strict
# frozen_string_literal: true

module Dependabot
  class PullRequestsService
    SKIPPED_USER_COMMIT_PATTERN = T.let(
      %r{\[dependabot[\s\-_]skip\]|\[skip[\s\-_]dependabot\]}i.freeze,
      Regexp
    )

    sig { params(repository: Repository, dependabot_user: User).void }
    def initialize(repository:, dependabot_user:)
      @repository = repository
      @dependabot_user = dependabot_user
    end

    sig { params(pr_numbers: T::Array[Integer], state: T.nilable(String), with_commits: T::Boolean).returns(T::Array[PullRequest]) }
    def find_pull_requests(pr_numbers: [], state: nil, with_commits: false)
      scope = repository.pull_requests.
          filter_spam_for(dependabot_user, skip_user_filter_if_not_spammy: true).
          joins(:issue).
          where(user: dependabot_user, issue: { number: pr_numbers })

      scope = scope.where(issue: { state: state }) if state.present?

      prs = scope.to_a
      GitHub::PrefillAssociations.prefill_batch_method(prs, :prelude_changed_commits) if with_commits

      prs
    end

    sig { params(pr: PullRequest, include_skipped_commits: T::Boolean).returns(T::Boolean) }
    def pr_has_user_commits?(pr:, include_skipped_commits:)
      pr.changed_commits.any? do |commit|
        next false if commit.author == dependabot_user
        next true if include_skipped_commits

        commit.message !~ SKIPPED_USER_COMMIT_PATTERN
      end
    end

    private

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(User) }
    attr_reader :dependabot_user
  end
end
