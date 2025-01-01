# typed: strict
# frozen_string_literal: true

module Orgs
  module ITeam
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(String)) }
    def slug; end

    sig { abstract.returns(T.nilable(String)) }
    def name; end

    sig { abstract.returns(T::Boolean) }
    def business_team?; end

    sig { abstract.params(user: T.nilable(T.any(User, Users::IUser))).returns(T::Boolean) }
    def member?(user); end

    sig { abstract.params(user: T.nilable(User)).returns(T::Boolean) }
    def visible_to?(user); end

    sig { abstract.params(repo: Repository, perm: T.any(String, Symbol), allow_different_owner: T::Boolean, repo_ids: T::Array[Integer]).returns(Team::ModifyRepositoryStatus) }
    def add_repository(repo, perm, allow_different_owner: false, repo_ids: nil); end

    sig { abstract.params(repo: ::Repositories::IRepository, perm: T.any(String, Symbol), context: T::Hash[Symbol, T.untyped]).returns(Team::ModifyRepositoryStatus) }
    def update_repository_permission(repo, perm, context: {}); end

    sig { abstract.params(repo: ::Repositories::IRepository, inline_fork_cleanup: T::Boolean).void }
    def remove_repository(repo, inline_fork_cleanup: false); end
  end
end
