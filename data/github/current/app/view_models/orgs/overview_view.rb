# typed: true
# frozen_string_literal: true

class Orgs::OverviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Users::OrganizationEnforcementMethods
  include TextHelper
  include RichwebHelper
  include PlatformHelper
  include UrlHelpers
  include BusinessesHelper
  include GitHub::Memoizer

  attr_reader :organization, :breadcrumb, :selected_nav_item, :show_new_business_org_message,
              :finished_migration, :rate_limited

  def page_title
    organization.safe_profile_name
  end

  def show_header?
    [
      organization_location,
      organization_blog,
      show_organization_social_accounts?,
      organization_profile_email(logged_in: logged_in?)
    ].any?(&:present?) || show_organization_enterprise?
  end

  def organization_login
    organization.display_login
  end

  def organization_avatar(avatarSize, avatarClass)
    helpers.avatar_for(organization, avatarSize, itemprop: "image", class: avatarClass)
  end

  def organization_avatar_url(avatarSize)
    helpers.avatar_url_for(organization, avatarSize)
  end

  def organization_location
    organization.profile_location
  end

  def organization_blog
    organization.profile_blog
  end

  def show_organization_social_accounts?
    organization_social_accounts.any?
  end

  def organization_social_accounts
    Array(organization.profile_social_accounts)
  end

  def organization_profile_email(logged_in: false)
    organization.publicly_visible_email(logged_in: logged_in)
  end

  def show_organization_enterprise?
    return @show_organization_enterprise if defined? @show_organization_enterprise

    @show_organization_enterprise = \
      logged_in? &&
      organization_enterprise.present? &&
      organization_enterprise.readable_by?(current_user)
  end

  def organization_enterprise
    return @organization_enterprise if defined? @organization_enterprise

    @organization_enterprise = organization.business
  end

  # Add the appropriate classes for the org header's meta data.
  def meta_classes(logged_in: false)
    classes = []
    classes << "has-location" if organization_location.present?
    classes << "has-blog"     if organization_blog.present?
    classes << "has-email"    if organization_profile_email(logged_in: logged_in).present?
    classes.join " "
  end

  def organization_developer_program_member?
    organization.developer_program_member?
  end

  def pending_invitation
    @pending_invitation ||= organization.pending_invitation_for(current_user)
  end

  def business_invitations
    organization.business_invitations_acceptable_by(current_user).joins(:business)
  end

  def show_role?
    pending_invitation && pending_invitation.billing_manager?
  end

  def accept_invitation_path
    if pending_invitation.billing_manager?
      urls.org_show_pending_billing_manager_invitation_path(organization)
    else
      urls.org_show_invitation_path(organization)
    end
  end

  def discussions_count
    @discussions_count ||= discussions_scope.count
  end

  def repositories_count
    @repositories_count ||= repositories_scope.count
  end

  def public_repositories_count
    @public_repositories_count ||= organization.public_repositories.count
  end

  def show_admin_stuff?
    adminable_by_current_user?
  end

  # Public: Should we show 2fa information
  #
  # Returns a boolean.
  def show_2fa?
    return false if organization.enterprise_managed_user_enabled?
    show_admin_stuff? && GitHub.auth.two_factor_authentication_enabled?
  end

  # Public: Should we show SAML SSO information
  #
  # Returns a boolean.
  def show_saml_sso?
    return false if organization.enterprise_managed_user_enabled?
    show_admin_stuff? && organization.saml_sso_present?
  end

  # Public: Should we show SAML SSO information
  #
  # Returns a boolean.
  def show_organization_membership?
    show_admin_stuff? && organization.scim_managed_enterprise?
  end

  def manager_org_settings_path
    if billing_manager?
      urls.settings_org_billing_path(organization)
    end
  end

  def show_new_team_button?
    organization.can_create_team?(current_user)
  end

  def show_import_teams_button?
    GitHub.ldap_sync_enabled? && adminable_by_current_user?
  end

  def discussions_scope
    organization.discussion_posts.visible_to(current_user)
  end

  def repositories_scope(org_owned_repo_ids: nil)
    @repositories_scope ||= organization.visible_repositories_for(current_user, org_pinned_repo_ids: org_owned_repo_ids, limit_visible_internal_repos_to_org: true)
  end

  def viewer_invited?
    pending_invitation.present?
  end

  def viewer_opted_in?
    return false unless current_user
    !OrganizationInvitation::OptOut.opted_out?(org: organization, invitee: current_user)
  end

  def show_pending_team_change_parent_requests?
    false
  end

  # Public: Checks if this page is being rendered to a user who's come through the
  # Business > New Organization workflow. We pass a URL param that should trigger a plain text
  # success flash message to be rendered
  def show_new_business_org_message?
    show_new_business_org_message && organization.business
  end

  def per_seat_pricing_model
    Billing::PlanChange::PerSeatPricingModel.new \
      organization,
      seats: organization.seats,
      plan_duration: organization.plan_duration,
      new_plan: organization.plan
  end

  def can_add_or_invite_users?
    !organization.at_seat_limit? || organization.business.present?
  end

  def show_finished_migration_help?
    !!finished_migration
  end

  def show_org_membership_banner?
    return unless logged_in?
    return if current_user.dismissed_notice?("org_membership_banner")

    # Only show the banner to non-owners.
    organization.direct_member?(current_user) && !adminable_by_current_user?
  end

  def failed_invitations
    if defined? @failed_invitations
      return @failed_invitations
    end
    @failed_invitations = organization.active_failed_invitations
  end

  def pending_non_manager_invitations
    if defined? @pending_non_manager_invitations
      return @pending_non_manager_invitations
    end
    @pending_non_manager_invitations = organization.pending_non_manager_invitations.
        includes(invitee: :profile)
  end

  # Public: Should we show the failed invitations section?
  #
  # Returns a boolean.
  def show_failed_invitations?
    failed_invitations.any? && adminable_by_current_user?
  end

  # Public: Should we show the pending invitations section?
  #
  # Returns a boolean.
  def show_pending_invitations?
    pending_non_manager_invitations.any? && adminable_by_current_user?
  end

  # Public: Should we show invitations?
  #
  # Returns a boolean.
  def show_invitations?
    show_pending_invitations? || show_failed_invitations?
  end

  def manage_seats_path
    organization.has_downgradable_seats? ? remove_org_seats_path(organization) : org_seats_path(organization)
  end

  def show_verified_domains?
    verified_profile_domains_for_organization.any?
  end

  def verified_profile_domains_for_organization
    @verified_domains ||= organization.verified_profile_domains
  end

  # Internal: Is the current user a direct or team member of the current
  # organization. Memoized to prevent database roundtrips.
  #
  # Returns a Boolean.
  def direct_or_team_member?
    return @direct_or_team_member if defined? @direct_or_team_member
    @direct_or_team_member = organization.direct_or_team_member?(current_user)
  end

  # Internal: Is the current user a billing_manager of the current
  # organization. Memoized to prevent repeat database roundtrips.
  #
  # Returns a Boolean.
  def billing_manager?
    return @is_billing_manager if defined? @is_billing_manager
    @is_billing_manager = organization.billing_manager?(current_user)
  end

  def export_path
    urls.org_members_export_path(organization)
  end

  def show_export_button?
    GitHub.organization_members_export_enabled?
  end

  def show_follow_orgs_notice?
    return false unless logged_in?
    !current_user.dismissed_notice?(UserNotice::FOLLOW_ORGS_NOTICE)
  end

  memoize def is_enterprise_teams_org_assignment_enabled?
    return false unless organization && organization.business
    organization.business.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end

  private

  # Internal: Is the current organization adminable by the current user?
  # Memoized to prevent database roundtrips.
  #
  # Returns a Boolean.
  def adminable_by_current_user?
    return @adminable_by_current_user if defined? @adminable_by_current_user
    @adminable_by_current_user = organization.adminable_by?(current_user)
  end
end
