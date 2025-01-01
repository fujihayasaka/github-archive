# typed: true
# frozen_string_literal: true

class Orgs::TeamMembers::IndexPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include BusinessesHelper

  attr_reader :organization,
              :team,
              :role,
              :membership,
              :graphql_org,
              :immediate_members,
              :child_members,
              :members

  def show_team_maintainer_help_ui?
    return false if team.ldap_mapped?
    return false unless team.locally_managed?
    return false if current_user.dismissed_notice?("team_maintainers_banner")
    return false unless organization.adminable_by?(current_user)
    return false if team.legacy_owners?
    return false if team.maintainers.any? { |m| !m.suspended? }
    return false if organization.admins.any? { |a| !a.suspended? && team.member?(a) }
    true
  end

  def suggestions_placeholder_text
    "Add a person"
  end

  # Returns the `selected` class for the `select-menu-item` filter options
  # when the provided filter option matches the selected filter.
  def role_filter_select_class(filter)
    "selected" if role_filter_selected == filter
  end

  def enterprise_managed_user_enabled?
    !!organization&.enterprise_managed_user_enabled?
  end

  def group_provisioning_enabled?
    scim_managed_enterprise?(organization&.business)
  end

  def identity_provider
    return if team.locally_managed?
    organization&.team_sync_tenant&.provider_label
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def viewer_can_administer_team?
    @team_adminiable ||= team.adminable_by?(current_user)
  end

  def viewer_can_administer_enterprise_team?
    !!organization.business&.owner?(current_user)
  end

  def show_enterprise_label?
    team.enterprise_team_managed?
  end

  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def team_locally_managed?
    team.locally_managed?
  end

  def immediate_team_members_count
    @immediate_members_count ||= immediate_members.count
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def no_immediate_team_members?
    @no_immediate_team_members ||= immediate_membership? && !immediate_members.exists?
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def child_team_members_count
    @child_team_members_count ||= child_members.count
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def no_child_team_members?
    @no_child_team_members ||= child_team_membership? && !child_members.exists?
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def no_members?
    members.empty?
  end

  def pending_invitations
    @pending_invitations ||= begin
      if viewer_can_administer_team?
        team.pending_invitations.filter_spam_for(current_user)
      else
        []
      end
    end
  end

  def pending_membership_requests
    @pending_membership_requests ||= begin
      if viewer_can_administer_team?
        team.pending_team_membership_requests.filter_spam_for(current_user)
      else
        []
      end
    end
  end

  def pending_invitations_count
    @pending_invitations_count ||= pending_invitations.count + pending_membership_requests.count
  end

  def child_team_membership?
    membership.to_s.upcase == "CHILD_TEAM"
  end

  def immediate_membership?
    membership.to_s.upcase == "IMMEDIATE"
  end

  private

  # Returns a Symbol for the queried role.
  def role_filter_selected
    role&.to_s&.underscore&.to_sym || :everyone
  end
end
