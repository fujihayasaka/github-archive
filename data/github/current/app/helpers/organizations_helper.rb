# typed: true
# frozen_string_literal: true

module OrganizationsHelper
  include OrganizationParamsHelper
  include FeatureFlagHelper
  include Scientist
  include IntegrationManagerHelper
  include BillingSettingsHelper
  include RichwebHelper
  include ActionView::Helpers::CaptureHelper
  include TextHelper

  # How many stars a repo has to have before we show a message to the last
  # org admin suggesting they add other admins.
  STARGAZERS_THRESHOLD_FOR_SUCCESSOR_PROMPT = 1_000

  # Public: Set the header title to show on smaller screens based on the given Organization.
  #
  # org - an Organization
  def org_header_title(org)
    content_for :header_title do
      T.unsafe(self).link_to(org.display_login, T.unsafe(self).user_path(org), class: "Header-link")
    end
  end

  def this_organization_description
    return @this_organization_description if defined?(@this_organization_description)
    @this_organization_description = ERB::Util.h(
      GitHub::Goomba::ProfileBioPipeline.to_html(T.unsafe(self).send(:this_organization).profile_bio, {}),
    )
  end

  def this_organization_meta_description
    return @this_organization_meta_description if defined?(@this_organization_meta_description)
    title = T.unsafe(self).send(:this_organization).safe_profile_name
    description = strip_tags(this_organization_description).strip
    meta_description = I18n.t("profiles.meta_description",
      username: title, count: T.unsafe(self).send(:this_organization).public_repositories.count)
    @this_organization_meta_description = ERB::Util.h(
      opengraph_description(title, description, meta_description),
    )
  end

  def this_organization_followers_count
    return @this_organization_followers_count if defined?(@this_organization_followers_count)
    @this_organization_followers_count = T.unsafe(self).send(:this_organization).followers_count(viewer: T.unsafe(self).current_user)
  end

  def display_sso_notice?(organization, user)
    return false if organization.nil?
    saml_sso_banner = User::NoticesDependency::ORGANIZATION_NOTICES[:saml_sso_banner]
    organization.async_notices_for(viewer: user).sync.include?(saml_sso_banner)
  end

  def display_organization_notice?(organization, user, notice_key, for_whole_org: false)
    return false if organization.nil?
    return false unless User::NoticesDependency::ORGANIZATION_NOTICES.key?(notice_key)
    notice = User::NoticesDependency::ORGANIZATION_NOTICES[notice_key]
    !user.dismissed_organization_notice?(notice, organization, for_whole_org: for_whole_org)
  end

  def display_saml_prompt?(organization, user)
    return if GitHub.enterprise?
    return if organization.nil? || user.nil?
    return unless display_organization_notice?(organization, user, :saml_prompt)
    return if organization.enterprise_managed_user_enabled?
    organization.eligible_for_org_enterprise_cloud_trial? && !organization.business_plus? && !organization.saml_sso_present?
  end

  def show_appoint_successor_prompt_for?(repository:, organization: nil)
    return false if GitHub.enterprise?
    return false unless T.unsafe(self).logged_in?

    organization ||= repository.owner
    notice = User::NoticesDependency::ORGANIZATION_NOTICES[:add_successor_prompt]

    repository.stargazer_count > STARGAZERS_THRESHOLD_FOR_SUCCESSOR_PROMPT &&
      !T.unsafe(self).current_user.dismissed_organization_notice?(notice, organization) &&
      organization.last_admin?(T.unsafe(self).current_user)
  end

  #
  # Filters
  #

  # Routes using this filter are available only to members of the
  # current organization.
  def org_members_only
    T.unsafe(self).render_404 if current_organization.nil?
  end

  # Routes using this filter are available only to admins of the
  # current organization.
  def org_admins_only
    T.unsafe(self).render_404 unless org_admin?
  end

  # Routes using this filter are available only to org admins or billing managers
  # of the current organization.
  def org_billing_management_only
    T.unsafe(self).render_404 unless org_billing_manageable?
  end

  def org_ref_rules_manager_only
    T.unsafe(self).render_404 unless org_ref_rules_manager?
  end

  def org_custom_properties_manager_or_editor_only
    T.unsafe(self).render_404 unless org_custom_properties_definitions_manager? || org_custom_properties_values_editor?
  end

  def org_custom_properties_definitions_manager_only
    T.unsafe(self).render_404 unless org_custom_properties_definitions_manager?
  end

  def this_organization_required
    T.unsafe(self).render_404 if current_organization.nil? || current_organization.deleted?
  end

  #
  # Controller & View Helpers
  #

  def orgs_rate_limit_filter
    T.unsafe(self).current_user.present?
  end

  # Returns an organization only if it exists and the current user has
  # access to it.
  def current_organization
    return @current_organization if defined?(@current_organization)

    if id = org_login_param || T.unsafe(self).params[:id]
      if T.unsafe(self).logged_in?
        org = find_org_accessible_by_current_user(id)
        @current_organization = org if org
      end
    end

    @current_organization
  end

  def find_org_accessible_by_current_user(org_login)
    org = Organization.find_by_login(org_login)
    org if org&.direct_or_team_member?(T.unsafe(self).current_user) ||
      org&.adminable_by?(T.unsafe(self).current_user) ||
      org&.billing_manager?(T.unsafe(self).current_user)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_organization
  end

  def show_corporate_tos_banner?
    return false if GitHub.enterprise?
    return false unless org_admin?
    return false if T.unsafe(self).current_user.dismissed_notice?("org_corporate_tos_banner")
    terms_of_service = current_organization.terms_of_service

    # allow excluded plans, non-standard TOS, and 1 member orgs if staff enabled this prompt
    if terms_of_service.corporate_upgrade_prompt_enabled?
      !terms_of_service.business_terms_of_service?
    else
      excluded_plan_names = %w[free free_with_addons pro custom300 hackathon500 contest engineyard enterprise]
      !excluded_plan_names.include?(current_organization.plan.name) &&
      terms_of_service.standard? &&
      current_organization.members_count > 1
    end
  end

  def show_esa_education_tos_banner?
    return false if GitHub.enterprise?
    return false unless org_admin?
    return false if T.unsafe(self).current_user.dismissed_notice?("org_esa_education_tos_banner")

    terms_of_service = current_organization.terms_of_service
    terms_of_service.esa_education_upgrade_prompt_enabled? && !terms_of_service.esa_education?
  end

  # Returns an organization only if it exists and the current user has
  # access to it as a direct or team member or a billing manager.
  def current_organization_for_member_or_manager
    current_organization_for_member_or_billing
  end

  # Returns an organization only if it exists and the current user has
  # access to it as a direct or team member, or a billing manager
  def current_organization_for_member_or_billing
    return @current_organization_for_member_or_billing if defined?(@current_organization_for_member_or_billing)

    if id = org_login_param || T.unsafe(self).params[:id]
      if T.unsafe(self).logged_in?
        org = Organization.find_by_login(id)
        @current_organization_for_member_or_billing = org if org && (org.direct_or_team_member?(T.unsafe(self).current_user) || org.billing_manager?(T.unsafe(self).current_user) || org.adminable_by?(T.unsafe(self).current_user))
      end
    end

    @current_organization_for_member_or_billing
  end

  #
  # View Helpers
  #

  # Is the logged in user an owner of the current organization?
  def org_admin?(org = current_organization)
    T.unsafe(self).logged_in? && org && org.adminable_by?(T.unsafe(self).current_user)
  end

  def org_moderator?
    T.unsafe(self).logged_in? && current_organization && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_moderator]
  end

  def org_ref_rules_manager?
    T.unsafe(self).logged_in? && current_organization && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_ref_rules_manager]
  end

  def org_custom_properties_definitions_manager?
    T.unsafe(self).logged_in? && current_organization && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_custom_properties_definitions_manager]
  end

  def org_custom_properties_values_editor?
    T.unsafe(self).logged_in? && current_organization && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_custom_properties_values_editor]
  end

  def can_manage_code_security_settings?
    T.unsafe(self).logged_in? && current_organization && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_code_security_manager]
  end

  def org_apps_manager?
    T.unsafe(self).logged_in? && current_organization && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_app_manager]
  end

  # Public: Is the logged in user a billing manager of the current organization?
  def org_billing_manager?(org = current_organization)
    T.unsafe(self).logged_in? && org && current_organization.org_settings_permissions_hash(T.unsafe(self).current_user)[:is_billing_manager]
  end

  def org_billing_manageable?(org = current_organization_for_member_or_billing)
    T.unsafe(self).logged_in? && org && (
      org.adminable_by?(T.unsafe(self).current_user) || org.billing_manager?(T.unsafe(self).current_user)
    )
  end

  def more_seats_link_for_organization(organization, **options)
    more_seats_link(
      organization,
      **options,
    )
  end

  def more_seats_link(organization, self_serve_link_text: "Buy more", self_serve_return_to: nil)
    return if Billing::EnterpriseCloudTrial.new(organization).block_seat_change?
    return unless organization.business&.owner?(T.unsafe(self).current_user)

    T.unsafe(self).link_to(self_serve_link_text, T.unsafe(self).org_seats_path(organization.display_login, return_to: self_serve_return_to), class: "Link--inTextBlock")
  end

  # Are we in the process of transforming a user into an organization?
  def org_transform?
    T.unsafe(self).params[:transform_user]
  end

  def business_plus_chosen?
    T.unsafe(self).params[:plan] == "business_plus"
  end

  # Under github.com, the organization contact email is called the "Billing
  # Email" while under Enterprise it's called the "Contact Email".
  def org_contact_email_label
    if GitHub.billing_enabled?
      "Billing"
    else
      "Contact"
    end
  end

  def pending_installation_requests?
    org_admin? && IntegrationInstallationRequest.where(target: current_organization).exists?
  end

  def current_org_enterprise_member_privileges_path
    business = current_organization.business
    if business&.owner?(T.unsafe(self).current_user)
      T.unsafe(self).settings_member_privileges_enterprise_path(business)
    end
  end

  def show_onboarding_component?(organization)
    return false if GitHub.enterprise?
    return false unless organization&.organization?
    return false unless T.unsafe(self).logged_in?
    return false if organization.archived?
    return false unless display_organization_notice?(organization, T.unsafe(self).current_user, :enterprise_trial_onboarding, for_whole_org: true)
    return false unless organization.adminable_by?(T.unsafe(self).current_user)
    return false if organization.enterprise_managed_user_enabled?

    Onboarding::Organization.new(organization).enabled?
  end

  def show_profile_toggle?(organization)
    return unless T.unsafe(self).logged_in?
    return if organization.enterprise_managed_user_enabled?
    organization.member?(T.unsafe(self).current_user)
  end

  def org_for_startup?(organization)
    @orgs_for_startup ||= {}
    return @orgs_for_startup[organization.id] if @orgs_for_startup.key?(organization.id)

    enterprise = organization.business
    is_org_for_startup = enterprise.present? && enterprise.part_of_startup_program?
    @orgs_for_startup[organization.id] = is_org_for_startup

    is_org_for_startup
  end

  # Public: Get the display version of the role for an invitation.
  #
  # invitation - Either an OrganizationInvitation or a RepositoryInvitation.
  #
  # Returns String
  def invitation_display_role(invitation)
    case invitation
    when OrganizationInvitation
      if invitation.role == "direct_member"
        "Member"
      else
        invitation.role.to_s.humanize
      end
    when RepositoryInvitation
      "Outside collaborator"
    end
  end
end
