# typed: strict
# frozen_string_literal: true

module Repositories
  class CreateRepositoryAttributes < T::Struct
    # The intended owner of the repository. Assumes the owner will be the actor when nil.
    # If a string is provided, it is assumed to represent the login of the intended owner who will
    # be resolved internally.
    prop :owner, T.nilable(T.any(String, Users::IUser))

    # TODO: This needs to default to `nil` until https://github.com/github/repos/issues/11178 is resolved.
    prop :name, T.nilable(String)

    prop :description, T.nilable(String)
    prop :visibility, RepositoryVisibility
    prop :template, T::Boolean, default: false
    prop :homepage, T.nilable(T.any(String, Addressable::URI))
    prop :has_wiki, T::Boolean, default: true
    prop :has_issues, T::Boolean, default: true
    prop :has_downloads, T::Boolean, default: true
    prop :has_discussions, T::Boolean, default: false

    # TODO: This needs to default to `nil` until https://github.com/github/repos/issues/11178 is resolved.
    prop :has_projects, T.nilable(T::Boolean)

    prop :gitignore_template, T.nilable(String)
    prop :license_template, T.nilable(String)
    prop :auto_init, T::Boolean, default: false

    # TODO: These should be part of a struct for a future "update merge settings" mutation.
    # See https://github.com/github/pull-requests/issues/11401
    prop :allow_merge_commit, T::Boolean, default: true
    prop :allow_squash_merge, T::Boolean, default: true
    prop :allow_rebase_merge, T::Boolean, default: true
    prop :allow_auto_merge, T::Boolean, default: false
    prop :delete_branch_on_merge, T::Boolean, default: false
    prop :allow_update_branch, T::Boolean, default: false
    prop :use_squash_pr_title_as_default, T::Boolean, default: false
    prop :squash_merge_commit_message, T.nilable(Repositories::SquashCommitMessage)
    prop :squash_merge_commit_title, T.nilable(Repositories::SquashCommitTitle)
    prop :merge_commit_title, T.nilable(Repositories::MergeCommitTitle)
    prop :merge_commit_message, T.nilable(Repositories::MergeCommitMessage)

    # TODO: This creates a dependency cycle from repos onto orgs/teams and should be moved into a dedicated mutation.
    # See https://github.com/github/Identity-Teams/issues/1108
    prop :team_id, T.nilable(Integer)

    # TODO (mclark): Hopefully we can remove this and generate the reflog data from the GitHub context and other params.
    prop :reflog_data, T.nilable(T::Hash[T.untyped, T.untyped])
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      serialize.transform_keys(&:to_sym)
    end
  end
end
