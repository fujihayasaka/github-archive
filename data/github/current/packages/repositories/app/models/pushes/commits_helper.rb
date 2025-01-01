# typed: strict
# frozen_string_literal: true

module Pushes
  module CommitsHelper
    extend T::Helpers

    abstract!

    include Kernel

    COMMITS_SUMMARY_LIMIT = 20

    # Helper for figuring out the commits involved in the push.
    # Requires: before, after, ref, repository
    #
    # String SHA of the ref before the push.
    sig { abstract.returns(String) }
    def before; end

    # String SHA of the ref after the push.
    sig { abstract.returns(String) }
    def after; end

    # String name of the ref: "refs/heads/master"
    sig { abstract.returns(String) }
    def ref; end

    # The Repository instance for this Push.
    sig { abstract.returns(T.nilable(Repositories::IRepository)) }
    def repository; end

    LARGE_PUSH_THRESHOLD = 2048 # 2k commits
    LARGE_REF_COUNT_THRESHOLD = 1000
    LARGE_BRANCH_COUNT_THRESHOLD = 5000

    sig { returns(T::Array[::Commit]) }
    def commits
      return [] unless repository
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

      @commits ||= T.let(
        begin
          oids = if deleted?
            []
          elsif created?
            repo.rpc.rev_list(after, reverse: true)
          else
            repo.rpc.rev_list(after, exclude_oids: before, reverse: true)
          end
          oids = oids[oids.size - 1000, 1000] if oids.size > 1000
          repo.commits.find(oids)
        rescue GitRPC::ObjectMissing
          return []
        end,
      T.nilable(T::Array[::Commit]))
    end

    sig { params(limit: Integer).returns(T::Array[T::Array[T.any(String, String, String, String, T::Boolean)]]) }
    def commits_summary(limit = COMMITS_SUMMARY_LIMIT)
      commits.first(limit).map do |commit|
        [commit.oid, commit.author_email, commit.message, commit.author_name, distinct_commit?(commit)]
      end
    end

    sig { returns(Integer) }
    def total_commits_count
      return 0 unless repository
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

      oids = if deleted?
        []
      elsif created?
        repo.rpc.rev_list(after, reverse: true)
      else
        repo.rpc.rev_list(after, exclude_oids: before, reverse: true)
      end
      commit_count = oids.size
      oids = oids[oids.size - 1000, 1000] if oids.size > 1000

      # Since we have already gone to rpc to find the commits,
      # we might as well cache them here to save on any future calls to commits.
      @commits = repo.commits.find(oids)
      commit_count
    rescue GitRPC::ObjectMissing
      0
    end

    sig { returns(T::Array[String]) }
    def rev_list
      return [] unless repository
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

      @rev_list ||= T.let(
        if deleted?
          []
        elsif created?
          repo.rpc.rev_list(after, reverse: true)
        else
          repo.rpc.rev_list(after, exclude_oids: before, reverse: true)
        end,
      T.nilable(T::Array[String]))
    rescue GitRPC::ObjectMissing
      []
    end

    sig { returns(T::Boolean) }
    def ref_is_tag?
      ref.to_s.start_with?("refs/tags/")
    end

    sig { returns(T::Boolean) }
    def ref_is_branch?
      ref.to_s.start_with?("refs/heads/")
    end

    sig { returns(T::Boolean) }
    def branch_or_tag?
      !!(ref.to_s =~ %r{\Arefs/(?:heads|tags)/})
    end

    sig { returns(T::Boolean) }
    def is_note?
      ref.to_s.start_with?("refs/notes/")
    end

    sig { returns(String) }
    def branch_name
      @branch_name ||= T.let(ref.to_s.sub(%r{\Arefs/(?:heads|tags)/}, ""), T.nilable(String))
    end

    alias tag_name branch_name

    sig { returns(String) }
    def branch_head
      @branch_head ||= T.let("#{ref}@{#{after}}", T.nilable(String))
    end

    # The branch was created on this push.
    sig { returns(T::Boolean) }
    def created?
      before == GitHub::NULL_OID
    end

    # The branch was deleted on this push.
    sig { returns(T::Boolean) }
    def deleted?
      after == GitHub::NULL_OID
    end

    # Check if push was a non-fast-forward push, and could only happen with `--force` flag used.
    #
    # Usually, the push command refuses to update a remote ref that is not an ancestor of the local ref.
    # In such cases `--force` flag needs to be used, and it can cause the remote repository to lose commits.
    #
    # However, simply applying `--force` flag to any push doesn't necessarily make it a non-fast-forward/force push.
    # A non-fast-forward explicitly means history was lost from the target ref.
    #
    # Ref creations aren't considered non-fast-forwards because they only append history.
    # Ref deletions aren't considered non-fast-forwards, they are special cases.
    #
    # Returns true when update was a non-fast-forward, otherwise false.
    sig { returns(T::Boolean) }
    def non_fast_forward?
      !created? && !deleted? && before != merge_base_commit_sha
    end

    sig { returns(T::Boolean) }
    def large_push?
      commits_pushed_count > LARGE_PUSH_THRESHOLD
    end

    # Common ancestor commit for before and after revs.
    sig { returns(T.nilable(String)) }
    def merge_base_commit_sha
      return unless repository

      @merge_base_commit_sha ||= T.let(
        begin
          T.cast(repository, Repository).rpc.merge_base(before, after) # rubocop:todo GitHub/AvoidCast
        rescue GitRPC::InvalidObject, GitRPC::InvalidFullOid
          ""
        end,
      T.nilable(String))
    end

    sig { returns(Integer) }
    def commits_pushed_count
      return 0 unless repository
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

      @commits_pushed_count ||= T.let(
        case
        when deleted?
          0
        when created?
          begin
            repo.rpc.distinct_commits(branch_head, count: true, new_syntax: true)
          rescue GitRPC::CommandFailed
            0
          end
        else
          begin
            repo.rpc.distinct_commits(branch_head, exclude: [before], count: true, new_syntax: true)
          rescue GitRPC::CommandFailed
            0
          end
        end,
      T.nilable(Integer))
    end

    sig { returns(T::Array[::Commit]) }
    def distinct_commits_pushed
      return [] unless repository
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

      @distinct_commits_pushed ||= T.let(
        begin
          oids = begin
            repo.rpc.distinct_commits(branch_head, exclude: [before], new_syntax: true)
          rescue GitRPC::CommandFailed
            []
          end
          return [] if oids.blank?
          repo.commits.find(oids).reverse
        end,
      T.nilable(T::Array[::Commit]))
    end

    sig { returns(T::Set[String]) }
    def distinct_set
      @distinct_set ||= T.let(Set.new(distinct_commits_pushed.map(&:oid)), T.nilable(T::Set[String]))
    end

    sig { params(commit: ::Commit).returns(T::Boolean) }
    def distinct_commit?(commit)
      distinct_set.include?(commit.oid)
    end

    sig { returns(T::Array[::Commit]) }
    def commits_pushed
      return [] unless repository
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast

      @commits_pushed ||= T.let(
        case
        when deleted?
          []
        when created?
          verify_valid_before_and_after_values
          oids = begin
            repo.rpc.distinct_commits(branch_head, new_syntax: true)
          rescue GitRPC::CommandFailed
            []
          end
          repo.commits.find(oids).reverse
        when non_fast_forward?
          verify_valid_before_and_after_values
          distinct_commits_pushed
        else
          verify_valid_before_and_after_values
          oids = repo.rpc.rev_list(after, exclude_oids: before, reverse: true)
          oids = oids[oids.size - 1000, 1000] if oids.size > 1000
          repo.commits.find(oids)
        end,
      T.nilable(T::Array[::Commit]))
    end

    sig { returns(T::Array[::Commit]) }
    def commits_pushed_limited
      commits = commits_pushed
      commits = [] if commits.count > LARGE_PUSH_THRESHOLD
      commits
    end

    class InvalidPushData < StandardError
    end

    sig { returns(NilClass) }
    def verify_valid_before_and_after_values
      if !GitRPC::Util.valid_full_oid?(before) || !GitRPC::Util.valid_full_oid?(after)
        raise InvalidPushData, "Invalid before or after commit oids. Must be 40 char SHA1s."
      end
    end
  end
end
