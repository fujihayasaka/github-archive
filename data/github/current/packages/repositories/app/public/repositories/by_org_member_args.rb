# typed: strict
# frozen_string_literal: true

module Repositories
  class ByOrgMemberArgs < T::Struct
    extend T::Sig

    # required
    prop :organization, Organization
    prop :pagination, GH::Pagination::Base
    prop :permission, PlatformPermissionSwitch

    # optional
    prop :user, T.nilable(User)
    prop :affiliations, T.nilable(T::Array[Repositories::RepositoryAffiliation])
    prop :default_affiliations, T.nilable(T::Array[Repositories::RepositoryAffiliation])
    prop :direction, GH::Pagination::Sort::Direction, default: GH::Pagination::Sort::Direction::ASC
    prop :has_issues_enabled, T.nilable(T::Boolean)
    prop :is_archived, T.nilable(T::Boolean)
    prop :is_fork, T.nilable(T::Boolean)
    prop :is_locked, T.nilable(T::Boolean)
    prop :privacy, T.nilable(Repositories::RepositoryVisibility)
    prop :sort, Repositories::SortBy, default: Repositories::SortBy::Id
    prop :sponsorable_only, T.nilable(T::Boolean)
    prop :finder_type, String, default: RepositoriesFinder::REPO_TYPE_DEFAULT
    prop :type, T.nilable(Repositories::RepositoryType)
    prop :unauthorized_organization_ids, T.nilable(T::Array[Integer])
    prop :visibility, T.nilable(Repositories::RepositoryVisibility)
    prop :filter_spam, T::Boolean, default: true

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      values = serialize.transform_keys(&:to_sym)

      values[:order_by] = { "field": values[:sort].first, "direction": values[:direction] }

      values.except(
        :direction,
        :finder_type,
        :organization,
        :pagination,
        :permission,
        :sort,
        :unauthorized_organization_ids,
        :user,
      )
    end
  end
end
