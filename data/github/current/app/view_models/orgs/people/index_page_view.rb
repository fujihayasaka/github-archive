# typed: true
# frozen_string_literal: true

class Orgs::People::IndexPageView < Orgs::OverviewView
  MAX_MODAL_INVITATIONS = 90
  MEMBERS_PER_PAGE = 30

  attr_reader :organization, :page, :query, :role

  def page_title
    "People · #{organization.safe_profile_name}"
  end

  def members
    return @members if defined? @members

    @members = found_members.paginate(page: page, per_page: MEMBERS_PER_PAGE)
  end

  def guest_collaborators
    return @guest_collaborators if defined? @guest_collaborators

    @guest_collaborators = organization.guest_collaborators(query)
  end

  def outside_collaborators_view
    Orgs::People::OutsideCollaboratorsView.new(
      organization: organization,
      page: page,
      query: query,
    )
  end

  def show_toolbar?
    !show_no_members_for_non_member?
  end

  def show_no_results?
    query.present? && no_members?
  end

  def show_no_members_for_non_member?
    no_members? &&
      !people_query.searching? &&
      !@role &&
      !organization.direct_or_team_member?(current_user)
  end

  def show_members?
    members.present?
  end

  def no_members?
    members.empty?
  end

  def show_buy_seats_link?
    unless organization.business&.trial?
      organization.plan.per_seat? && !organization.has_unlimited_seats? && organization.adminable_by?(current_user)
    end
  end

  def show_org_membership_banner?
    return unless logged_in?
    return if current_user.dismissed_notice?("org_membership_banner")

    # Only show the banner to non-owners.
    organization.direct_member?(current_user) && !organization.adminable_by?(current_user)
  end

  # Public: Should we show the invitations section?
  #
  # Returns a boolean.
  def show_pending_invitations_view_more?
    pending_non_manager_invitations.size > MAX_MODAL_INVITATIONS
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def role_filter_select_class(filter)
    "selected" if role_filter_selected == filter
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def two_factor_filter_select_class(filter)
    "selected" if two_factor_filter_selected == filter
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def organization_membership_filter_select_class(filter)
    "selected" if organization_membership_filter_selected == filter
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def sso_filter_select_class(filter)
    "selected" if sso_filter_selected == filter
  end

  def members_count
    @members_count ||= found_members.size
  end

  private

  # Returns a Symbol for the queried role.
  def role_filter_selected
    @role_filter_selected ||= people_query.role_match || :all
  end

  # Returns a Symbol for the selected 2FA scope queried.
  def two_factor_filter_selected
    if organization.can_disallow_two_factor_methods?
      @two_factor_filter_selected ||=
        case
        when people_query.two_factor_secure_scope?
          :secure
        when people_query.two_factor_insecure_scope?
          :insecure
        when people_query.two_factor_disabled_scope?
          :disabled
        else
          :all
        end
    else
      @two_factor_filter_selected ||=
        case
        when people_query.two_factor_enabled_scope?
          :enabled
        when people_query.two_factor_disabled_scope?
          :disabled
        when people_query.two_factor_required_scope?
          :required
        else
          :all
        end
    end
  end

  # Returns a Symbol for the selected organization membership scope queried.
  def organization_membership_filter_selected
    @organization_membership_filter_selected ||=
      case
      when people_query.organization_membership_group_scope?
        :external_group
      when people_query.organization_membership_admin_scope?
        :admin
      else
        :all
      end
  end

  # Returns a Symbol for the selected SSO scope queried.
  def sso_filter_selected
    @sso_filter_selected ||=
      case
      when people_query.external_identity_linked_scope?
        :linked
      when people_query.external_identity_unlinked_scope?
        :unlinked
      else
        :all
      end
  end

  def people_query
    @people_query ||= Organization::People::Query.new(
      query: query,
      organization: organization,
      current_user: current_user,
      role: role,
    )
  end

  def found_members
    @found_members ||= begin
      users = Organization::People::Filter.new(query: people_query).call
      Organization::People::Search.new(query: people_query, users: users).call
    end
  end
end
