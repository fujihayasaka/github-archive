# typed: strict
# frozen_string_literal: true

module Repositories
  module Push
    extend T::Helpers

    abstract!
    requires_ancestor { Object }

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(T.nilable(String)) }
    def ref; end

    sig { abstract.returns(T.nilable(String)) }
    def before; end

    sig { abstract.returns(T.nilable(String)) }
    def after; end

    sig { abstract.returns(::ActiveSupport::TimeWithZone) }
    def created_at; end

    sig { abstract.returns(::ActiveSupport::TimeWithZone) }
    def pushed_at; end

    sig { abstract.returns(::ActiveSupport::TimeWithZone) }
    def updated_at; end

    sig { abstract.returns(T.nilable(Users::IUser)) }
    def pusher; end

    sig { abstract.returns(T::Boolean) }
    def non_fast_forward?; end

    sig { abstract.returns(String) }
    def branch_name; end

    sig { abstract.returns(T.nilable(Integer)) }
    def pusher_id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def repository_id; end

    sig { abstract.returns(String) }
    def push_type; end

    # Methods below were exposed from from Pushes::CommitsHelper:
    sig { abstract.returns(T::Array[::Commit]) }
    def commits; end

    sig { abstract.params(commits: T::Array[::Commit]).returns(T::Array[::Commit])  }
    def commits=(commits); end

    sig { abstract.returns(T::Array[T.nilable(::Commit)]) }
    def distinct_commits_pushed; end

    sig { abstract.returns(T::Array[T::Array[T.any(String, String, String, String, T::Boolean)]]) }
    def commits_summary; end

    sig { abstract.returns(T::Boolean) }
    def created?; end

    sig { abstract.returns(T::Boolean) }
    def deleted?; end

    sig { abstract.returns(T.nilable(Repositories::IRepository)) }
    def repository; end

    sig { abstract.returns(T::Array[::Commit]) }
    def commits_pushed; end

    sig { abstract.returns(T::Boolean) }
    def large_push?; end

    sig { abstract.params(decompose_renames: T::Boolean).returns(T.nilable(T::Array[Repositories::ChangedFile])) }
    def changed_files(decompose_renames: false); end

    sig { abstract.returns(T::Boolean) }
    def initial_commit?; end

    sig { abstract.returns(T::Boolean) }
    def ref_is_tag?; end

    sig { abstract.returns(T.nilable(T::Boolean)) }
    def on_default_branch?; end
  end
end
