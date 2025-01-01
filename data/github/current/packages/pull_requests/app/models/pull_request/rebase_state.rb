# typed: true
# frozen_string_literal: true

class PullRequest
  # Encapsulates whether a rebase for a PR was prepared and whether
  # the prepared rebase is safe to apply.
  class RebaseState
    def initialize(pull)
      @pull = pull
    end

    def prepared?
      return @prepared if defined? @prepared
      @prepared = @pull.mergeable? && ref.present?
    end

    def safe?
      return @safe if defined? @safe
      @safe = prepared? && ref.target.tree_oid == merge_commit.tree_oid
    end

    private

    def ref
      return @ref if defined? @ref
      @ref = @pull.repository.internal_refs.find(@pull.rebase_ref)
    end

    def merge_commit
      return @merge_commit if defined? @merge_commit
      @merge_commit = @pull.repository.commits.find(@pull.merge_commit_sha)
    end
  end
end
