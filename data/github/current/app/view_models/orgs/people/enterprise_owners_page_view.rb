# typed: true
# frozen_string_literal: true

class Orgs::People::EnterpriseOwnersPageView < Orgs::OverviewView
  OWNERS_PER_PAGE = 30

  attr_reader :organization, :page, :query, :role

  def page_title
    "Enterprise owners for · #{organization.safe_profile_name}"
  end

  def owners
    @owners ||= found_owners.paginate(page: page, per_page: OWNERS_PER_PAGE)
  end

  def show_member_stuff?
    return @show_member_stuff if defined? @show_member_stuff

    @show_member_stuff = organization.direct_or_team_member?(current_user)
  end

  def show_admin_stuff?
    return @show_admin_stuff if defined? @show_admin_stuff

    @show_admin_stuff = organization.adminable_by?(current_user)
  end

  def show_no_results?
    query.present? && !owners_present?
  end

  def owners_present?
    owners.present?
  end

  def owners_count
    @owners_count ||= found_owners.size
  end

  def role_filter_select_class(filter)
    "selected" if role_filter_selected == filter
  end

  def role_filter_selected
    if query_unaffiliated_owners?
      @role_filter_selected ||= :unaffiliated
    else
      @role_filter_selected ||= people_query.role_match || :all
    end
  end

  private

  def people_query
    @people_query ||= Organization::People::Query.new(
      query: query,
      organization: organization,
      current_user: current_user,
      role: role,
    )
  end

  def query_unaffiliated_owners?
    return false unless show_member_stuff?

    query&.include?("role:unaffiliated")
  end

  def query_membership_role?
    return false unless show_member_stuff?

    query&.include?("role:owner") || query&.include?("role:member")
  end

  def found_owners
    return [] unless show_member_stuff?  # Ensure only members of the organization can access this information

    @found_owners ||= begin
      if query_unaffiliated_owners?
        # Get all of the enterprise owners that are not a part of the organization
        organization.async_unaffiliated_enterprise_owners(query: query).sync
      elsif query_membership_role?
        # Get all of the enterprise owners given a specific organization role
        organization.async_affiliated_enterprise_owners(people_query: people_query).sync
      else
        # Don't filter by organization role, return all matching enterprise owners
        organization.async_enterprise_owners(query: query).sync
      end
    end
  end

  def viewer_role(role)
    # Get the string value of the role to be passed into the query
    # Platform::Enums::RoleInOrganization returns "direct_member" but
    # ::Business#filtered_organizations expects "member"
    return "member" if role == "member"
    return "owner" if role == "owner"
    nil
  end
end
