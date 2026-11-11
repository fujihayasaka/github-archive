# typed: true
# frozen_string_literal: true

class Stafftools::Spark::OrgInfoComponent < ApplicationComponent
  sig { params(organization: Organization).void }
  def initialize(organization:)
    @organization = organization
  end

  private

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(T.nilable(T::Boolean)) }
  def render?
    logged_in?
  end

  sig { returns(T::Array[Integer]) }
  memoize def member_user_ids
    organization.members.pluck(:id)
  end

  sig { returns(Integer) }
  memoize def users_with_sparks_count
    with_database_error_fallback(fallback: 0) do
      Spark::Workbench.where(user_id: member_user_ids).distinct.count(:user_id)
    end
  end

  sig { returns(Integer) }
  memoize def total_sparks_count
    with_database_error_fallback(fallback: 0) do
      Spark::Workbench.where(user_id: member_user_ids).count
    end
  end

  sig { returns(Integer) }
  memoize def sparks_shared_to_org_count
    with_database_error_fallback(fallback: 0) do
      # Find runtime apps that are:
      # 1. Set to selected_orgs visibility
      # 2. Have visibility_organization_id matching this organization
      Spark::Workbench.joins(:runtime_app)
        .where(runtime_app: {
          visibility: :selected_orgs,
          visibility_organization_id: organization.id
      }).count
    end
  end
end
