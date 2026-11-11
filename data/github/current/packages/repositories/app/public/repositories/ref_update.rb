# typed: strict
# frozen_string_literal: true

module Repositories
  class RefUpdate
    include Pushes::CommitsHelper
    include Pushes::ChangedFilesHelper

    sig { override.returns(String) }
    attr_reader :before

    sig { override.returns(String) }
    attr_reader :after

    sig { override.returns(String) }
    attr_reader :ref

    sig { override.returns(Repository) }
    attr_reader :repository

    sig { override.returns(User) }
    attr_reader :pusher

    sig { override.returns(T::Boolean) }
    attr_reader :spokes_api_fail_fast_enabled

    sig { params(commits: T.nilable(T::Array[::Commit])).returns(T.nilable(T::Array[::Commit])) }
    attr_writer :commits

    sig do
      params(
        before: String,
        after: String,
        ref: String,
        repository: Repository,
        pusher: User
      ).void
    end
    def initialize(before:, after:, ref:, repository:, pusher:)
      @before = T.let(before, String)
      @after = T.let(after, String)
      @ref = T.let(ref, String)
      @repository = T.let(repository, Repository)
      @pusher = T.let(pusher, User)
      @spokes_api_fail_fast_enabled = T.let(true, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def pages_branch?
      ref == "refs/heads/#{repository.pages_branch}"
    end

    sig { returns(T::Boolean) }
    def default_branch?
      ref == "refs/heads/#{repository.default_branch}"
    end

    sig { returns(T::Boolean) }
    def initial_commit?
      created? && !deleted?
    end

    # whether or not we'll store a Push record for this ref update
    sig { returns(T::Boolean) }
    def recordable?
      return false if is_note?
      return false if ref_is_tag? && !deleted?
      branch_or_tag?
    end
  end
end
