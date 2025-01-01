# typed: false
# frozen_string_literal: true

module SettingsHelper
  include OrganizationsHelper

  CONTEXT_DROPDOWN_MIN = 10

  def show_private_contribution_count?
    profile_settings = current_user.profile_settings
    profile_settings.show_private_contribution_count?
  end

  def achievements_enabled?
    profile_settings = current_user.profile_settings
    profile_settings.achievements_enabled?
  end

  def all_private_projects_opted_out_of_achievements_tracking?
    profile_settings = current_user.profile_settings
    profile_settings.all_private_projects_opted_out_of_achievements_tracking?
  end

  def pro_badge_enabled?
    profile_settings = current_user.profile_settings
    profile_settings.pro_badge_enabled?
  end

  def acv_badge_enabled?
    current_user.profile_settings.acv_badge_enabled?
  end

  def nasa_badge_enabled?
    current_user.profile_settings.nasa_badge_enabled?
  end

  def profile_heading_text
    "Public profile"
  end

  def profile_email_label_text
    "Public email"
  end

  def security_and_privacy_section_title
    "Account security"
  end

  def org_allowlist_selectable_class
    current_organization.restricts_oauth_applications? ? "is-selectable" : ""
  end

  def key_created_at_description(key)
    parts = []
    if key.created_at
      time = content_tag(:"relative-time", key.created_at.strftime("%b %-d, %Y"),
        datetime: key.created_at.utc.iso8601,
        threshold: "PT0S",
        month: "short",
        day: "numeric",
        year: "numeric")

      is_deploy_key = key.kind_of?(PublicKey) && key.repository_key?
      parts << "Added " << time
      if authorization = key.try(:oauth_authorization)
        user = content_tag("strong") { authorization.user.present? ? "@#{authorization.user.login}" : "a deleted user" }
        if authorization.personal_access_authorization?
          parts << " via personal access token"
          parts << " owned by " << user if is_deploy_key
        else
          app = content_tag("strong") { authorization.application.name }
          parts << " by " << app
          parts << " with authorization from " << user if is_deploy_key
        end
      elsif is_deploy_key && key.creator.present?
        user = content_tag("strong") { "@#{key.creator.login}" }
        parts << " by " << user
      end
    end
    safe_join parts
  end

  # Creates a case-insensitive pattern for use with a regex when the ignore
  # case flag cannot be added to the regex. Currently used for passing the
  # pattern used for HTML5/JavaScript validation when prompting users to enter
  # a login or repository name when deleting/transferring.
  #
  # Example:
  #   case_insensitive_pattern("MiXeD")
  #   # => "[mM][iI][xX][eE][dD]"
  #
  # input - An input string. Currently used for logins, repository names, and
  # name with owner ("owner/repo") values.
  #
  # Returns a String that can be used to do a case-insensitive match for the
  # input value.
  def case_insensitive_pattern(input)
    Regexp.escape(input)
      .gsub(/[a-zA-Z]/) { |ch| "[#{ch.downcase}#{ch.upcase}]" }
      .gsub(/\\([ #-])/, '\1')
  end

  # Creates a case-insensitive pattern to be used for validation when a user is
  # asked to enter their "username or email" as confirmation before deleting
  # their account. Accepts their login or any of their emails.
  #
  # Example:
  #   account_deletion_username_pattern(user)
  #   # => "[mM][aA][xX]|[mM][eE]@[mM][aA][xX].[iI][oO]|[mM][aA][xX]@[mM][eE].[cC][oO][mM]"
  #
  # user - The user being deleted.
  #
  # Returns a String that can be used as a pattern for validation of the
  # "username or email" input.
  def account_deletion_username_pattern(user)
    input_option_patterns = [case_insensitive_pattern(user.login)]
    user.emails.user_entered_emails.each do |email|
      input_option_patterns << case_insensitive_pattern(email.email)
    end
    input_option_patterns.join("|")
  end

  def selected_link?(link:)
    current_page?(link) || current_page?("#{link}/")
  end

  def switch_context_link(current_context:, target_context:, permission:)
    selected_member_feature_requests = selected_member_feature_requests?(current_context: current_context)
    selected_billing = selected_billing?(current_context: current_context)
    selected_plans = selected_plans?(current_context: current_context)
    selected_upgrade = selected_upgrade?(current_context: current_context)
    selected_security = selected_security?(current_context: current_context)

    if target_context.is_a?(Business)
      return settings_billing_enterprise_path(target_context) if selected_billing || selected_plans || permission == :billing_manager
      return settings_security_enterprise_path(target_context) if selected_security
      settings_profile_enterprise_path(target_context)
    elsif target_context.organization?
      return organization_settings_member_feature_requests_path(target_context) if selected_member_feature_requests && org_billing_manageable?(target_context)
      return settings_org_billing_path(target_context) if selected_billing || permission == :billing_manager
      return settings_org_plans_path(target_context) if selected_plans || permission == :billing_manager
      return upgrade_path(target: "organization", source: "account upgrade", org: target_context) if selected_upgrade || permission == :billing_manager
      return settings_org_security_path(target_context) if selected_security
      settings_org_profile_path(target_context)
    else
      return settings_user_billing_path if selected_billing
      return settings_user_plans_path if selected_plans
      return upgrade_path(target: "user", source: "account upgrade") if selected_upgrade
      return settings_security_path if selected_security
      settings_user_profile_path
    end
  end

  def selected_member_feature_requests?(current_context:)
    selected_link?(link: organization_settings_member_feature_requests_path(current_context))
  end

  def selected_billing?(current_context:)
    selected_link?(link: settings_user_billing_path) || selected_link?(link: settings_org_billing_path(current_context))
  end

  def selected_plans?(current_context:)
    selected_link?(link: settings_user_plans_path) || selected_link?(link: settings_org_plans_path(current_context))
  end

  def selected_upgrade?(current_context:)
    return false unless GitHub.billing_enabled?

    selected_link?(link: upgrade_path) || selected_link?(link: upgrade_path(target: "organization", source: "account upgrade", org: current_context))
  end

  def selected_security?(current_context:)
    selected_link?(link: settings_security_path) || selected_link?(link: settings_org_security_path(current_context))
  end

  def available_contexts(current_context:)
    all_contexts = {}

    if current_context.organization?
      all_contexts[current_user] = :user
    end

    current_user.owned_organizations.each { |org| all_contexts[org] = :admin }
    current_user.billing_manager_organizations.each { |org| all_contexts[org] ||= :billing_manager }
    current_user.businesses(membership_type: :admin).each { |business| all_contexts[business] = :admin }
    current_user.businesses(membership_type: :billing_manager).each { |business| all_contexts[business] ||= :billing_manager }
    all_contexts.reject do |context|
      (context.organization? && context.deleted) || context == current_context
    end
  end

  def settings_context_dropdown_attributes(event_context:, target:, target_name: nil, target_id: nil, target_link: nil, ga_attr: {})
    hydro_attributes = hydro_click_tracking_attributes(
      "settings_context_dropdown.click",
      user_id: current_user.id,
      event_context: event_context,
      target: target,
      target_name: target_name,
      target_id: target_id,
      target_link: target_link
    )

    safe_data_attributes(ga_attr.merge(hydro_attributes))
  end

  def tracking_target_type(context)
    case context
    when Organization then :ORG
    when User then :USER
    when Business then :BUSINESS
    end
  end

  def target_context_display_name(context)
    case context
    when User then context.display_login
    when Business then context.name
    end
  end

  def current_user_default_new_repo_branch
    @current_user_default_new_repo_branch ||= current_user.default_new_repo_branch
  end

  def upgrade_intent?
    request.query_parameters[:action].present? && (request.query_parameters[:action] == "upgrade")
  end

  def intended_plan_class
    plan = GitHub::Plan.find(params[:plan])
    if plan.present? && !plan.legacy?
      return plan
    end
    GitHub::Plan.free
  end

  def choose_account_verb
    if intended_plan_class.paid?
      "upgrade to GitHub " + intended_plan_class.display_name.humanize
    elsif upgrade_intent?
      "upgrade"
    else
      "manage"
    end
  end

  def account_has_upgrade_path?(account, plan: intended_plan_class)
    if account.organization?
      if plan.paid?
        return false if plan == account.plan
        return false if account.plan == GitHub::Plan.business_plus
        return false if plan == GitHub::Plan.pro
        true
      else
        true
      end
    else
      return false if plan == GitHub::Plan.business_plus
      return false if plan == GitHub::Plan.business
      true
    end
  end

  def choose_account_link(account)
    if account.organization?
      if intended_plan_class.paid?
        upgrade_path(
          plan: intended_plan_class,
          target: "organization",
          source: "choose account",
          org: account
        )
      elsif upgrade_intent?
        settings_org_plans_path(account)
      else
        settings_org_profile_path(account)
      end
    else
      upgrade_intent? ? settings_user_plans_path : settings_user_profile_path
    end
  end

  def settings_account_type(current_context)
    case current_context
    when Organization
      "organization"
    when User
      "personal"
    when Business
      "enterprise"
    end
  end

  def settings_account_path(current_context)
    return enterprise_path(current_context) if current_context.is_a?(Business)

    user_path(current_context)
  end

  def settings_account_label(current_context)
    if current_context.user?
      "Your #{settings_account_type(current_context)} account"
    else
      suffix = ""
      if belongs_to_business?(current_context)
        suffix = ", part of"
      elsif current_context.is_a?(Business)
        suffix = " account"
      end

      "#{settings_account_type(current_context)}#{suffix}".capitalize
    end
  end

  def belongs_to_business?(current_context)
    return false unless current_context.organization?

    current_context.business.present?
  end

  def parent_business_name(current_context)
    return unless belongs_to_business?(current_context)

    current_context.business.safe_profile_name
  end
end
