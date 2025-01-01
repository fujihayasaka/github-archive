# typed: strict
# frozen_string_literal: true

module Repositories
  module IPush
    extend T::Sig
    extend T::Helpers

    abstract!
    requires_ancestor { Object }

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(String) }
    def ref; end

    sig { abstract.returns(String) }
    def before; end

    sig { abstract.returns(String) }
    def after; end

    sig { abstract.returns(Time) }
    def created_at; end

    sig { abstract.returns(Time) }
    def pushed_at; end

    sig { abstract.returns(::User) }
    def pusher; end

    sig { abstract.returns(T::Boolean) }
    def non_fast_forward?; end

    sig { abstract.returns(String) }
    def branch_name; end

    sig { abstract.returns(Integer) }
    def pusher_id; end

    sig { abstract.returns(Integer) }
    def repository_id; end

    sig { abstract.returns(Integer) }
    def push_type; end

    sig { abstract.returns(IPush) }
    def reload; end

    # Methods below were exposed from from Pushes::CommitsHelper:
    sig { abstract.returns(T::Array[T.nilable(::Commit)]) }
    def commits; end

    sig { abstract.params(commits: T.nilable(T::Array[::Commit])).returns(NilClass) }
    def commits=(commits); end

    sig { abstract.returns(T::Array[T.nilable(::Commit)]) }
    def distinct_commits_pushed; end

    sig { abstract.returns(T::Array[T::Array[T.any(String, String, String, String, T::Boolean)]]) }
    def commits_summary; end

    sig { abstract.returns(T::Boolean) }
    def created?; end

    sig { abstract.returns(T::Boolean) }
    def deleted?; end

    sig { abstract.returns(Repository) }
    def repository; end

    sig { abstract.returns(T::Array[::Commit]) }
    def commits_pushed; end

    sig { abstract.returns(T::Boolean) }
    def large_push?; end

    sig { abstract.params(decompose_renames: T::Boolean).returns(T.nilable(T::Array[Repositories::Push::ChangedFile])) }
    def changed_files(decompose_renames: false); end

    sig { returns(T::Boolean) }
    def initial_commit?
      created? && !deleted?
    end
  end
end
