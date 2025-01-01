# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class FindPullRequest < Command
    attr_reader :owner, :repository, :ref

    def initialize(owner:, repository:, ref:)
      @owner, @repository, @ref = owner, repository, ref
    end

    def perform
      return if repository.nil?
      return if ref == repository.default_branch
      return unless repository.pushable_by?(owner, ref: ref)

      pulls = if owner.feature_enabled?(:codespaces_unscoped_find_pr)
        T.unsafe(PullRequest).find_open_based_on_head_ref(repository.id, ref)
      else
        T.unsafe(PullRequest).where(user: owner).find_open_based_on_head_ref(repository.id, ref)
      end
      # If there are multiple possible matching PRs ignore them all.
      pulls.one? ? pulls.first : nil
    rescue ActiveRecord::RecordNotFound
      # `find_open_based_on_head_ref` raises when an open PR exists for the ref but it's not
      # owned by the scoped user due to its internal implementation. We don't actually care
      # though and expect this to happen.
    end
  end
end
