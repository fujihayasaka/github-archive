# typed: true
# frozen_string_literal: true

module BusinessesHelper
  include GitHub::Memoizer
  include ActionView::Helpers::TextHelper
  include AvatarHelper

  TRIAL_ONBOARDING_NOTICE_NAME = "trial_onboarding"
  COPILOT_ONBOARDING_NOTICE_NAME = "copilot_getting_started"

  TWO_FACTOR_STATUS = {
    "ENABLED" => "enabled",
    "REQUIRED" => "required",
    "SECURE" => "secure",
    "INSECURE" => "insecure",
    "DISABLED" => "disabled",
  }.freeze

  ACCOUNT_TYPE = {
    "BUILT_IN" => "built_in",
    "SAML_LINKED" => "saml_linked",
    "SAML_AND_SCIM_LINKED" => "saml_and_scim_linked",
  }.freeze

  EXTERNAL_GROUP_SYNC_STATUS = {
    "SYNCED" => "synced",
    "NOT_SYNCED" => "not_synced",
    "NO_STATUS" => "no_status",
  }.freeze

  # License filters not currently in the Platform::Enums::EnterpriseLicenseType enum.
  # Can be removed once this filter is also supported in the API.
  ADDITIONAL_ENTERPRISE_LICENSE_TYPES = {
    "COPILOT" => "copilot",
    "NO_COPILOT" => "no_copilot"
  }.freeze

  ADDITIONAL_ENTERPRISE_LICENSE_TYPE_DESCRIPTIONS = {
    "copilot" => "Copilot license",
    "no_copilot" => "No Copilot license"
  }

  ORGANIZATION_QUERY_FILTERS = {
    viewer_role: {
      filter: /\bviewer_role:(\S+)/.freeze,
      multi: false,
    },
    has_deploy_keys: {
      filter: /\bhas_deploy_keys:(\S+)/.freeze,
      multi: false,
    },
    two_factor_policy: {
      filter: /\btwo_factor_policy:(\S+)/.freeze,
      multi: false,
    },
  }

  MEMBERS_QUERY_FILTERS = {
    role: {
      filter: /\brole:(\S+)/.freeze,
      multi: false,
      graphql_enum: Platform::Enums::EnterpriseUserAccountMembershipRole,
    },
    account_type: {
      filter: /\baccount_type:(\S+)/.freeze,
      multi: false,
      enum: ACCOUNT_TYPE,
    },
    organizations: {
      filter: /\borganization:(\S+)/.freeze,
      multi: true,
    },
    deployment: {
      filter: /\bdeployment:(\S+)/.freeze,
      multi: false,
      graphql_enum: Platform::Enums::EnterpriseUserDeployment,
    },
    license: {
      filter: /\blicense:(\S+)/.freeze,
      multi: false,
      enum: ADDITIONAL_ENTERPRISE_LICENSE_TYPES,
      graphql_enum: Platform::Enums::EnterpriseLicenseType,
    },
    two_factor_status: {
      filter: /\btwo_factor_status:(\S+)/.freeze,
      multi: false,
      enum: TWO_FACTOR_STATUS,
    },
    cost_center: {
      filter: /\bcost_center:(\S+)/.freeze,
      multi: false,
    }
  }

  EXTERNAL_GROUPS_QUERY_FILTERS = {
    sync_status: {
      filter: /\bsync_status:(\S+)/.freeze,
      multi: false,
      enum: EXTERNAL_GROUP_SYNC_STATUS,
    }
  }

  OUTSIDE_COLLABS_QUERY_FILTERS = {
    visibility: {
      filter: /\bvisibility:(\S+)/.freeze,
      multi: false,
      graphql_enum: Platform::Enums::RepositoryVisibility,
    },
    organizations: {
      filter: /\borganization:(\S+)/.freeze,
      multi: true,
    },
    two_factor_status: {
      filter: /\btwo_factor_status:(\S+)/.freeze,
      multi: false,
      enum: TWO_FACTOR_STATUS,
    },
  }

  ADMINS_QUERY_FILTERS = {
    organizations: {
      filter: /\borganization:(\S+)/.freeze, # https://rubular.com/r/mkU9p0ZcWIRAL4
      multi: true,
    },
    role: {
      filter: /\brole:(\S+)/.freeze,
      multi: false,
    },
    account_type: {
      filter: /\baccount_type:(\S+)/.freeze,
      multi: false,
      enum: ACCOUNT_TYPE,
    },
    two_factor_status: {
      filter: /\btwo_factor_status:(\S+)/.freeze,
      multi: false,
      enum: TWO_FACTOR_STATUS,
    },
    sort: {
      filter: /\bsort:((created|title)-(asc|desc))/.freeze,
      multi: false,
    },
  }

  UNAFFILIATED_QUERY_FILTERS = {
    two_factor_status: {
      filter: /\btwo_factor_status:(\S+)/.freeze,
      multi: false,
      enum: TWO_FACTOR_STATUS,
    },
    sort: {
      filter: /\bsort:((created|title)-(asc|desc))/.freeze,
      multi: false,
    },
  }


  USER_ACCOUNT_MEMBERSHIP_QUERY_FILTERS = {
    role: {
      filter: /\brole:(\S+)/.freeze,
      multi: false,
      graphql_enum: Platform::Enums::EnterpriseUserAccountMembershipRole,
    },
  }

  PENDING_MEMBERS_QUERY_FILTERS = {
    license: {
      filter: /\blicense:(\S+)/.freeze,
      multi: false,
      graphql_enum: Platform::Enums::EnterpriseLicenseType,
    },
    organizations: {
      filter: /\borganization:(\S+)/.freeze,
      multi: true,
    },
    source: {
      filter: /\bsource:(member|scim)/.freeze,
      multi: false,
    },
    sort: {
      filter: /\bsort:((created|title)-(asc|desc))/.freeze,
      multi: false
    }
  }

  OUTSIDE_COLLABORATORS_INVITATIONS_QUERY_FILTERS = {
    sort: {
      filter: /\bsort:(created-(asc|desc))/.freeze,
      multi: false
    }
  }

  FAILED_INVITATIONS_QUERY_FILTERS = {
    sort: {
      filter: /\bsort:((created|title)-(asc|desc))/.freeze,
      multi: false
    }
  }

  USER_NAMESPACE_REPOSITORY_FILTER = {
    sort: {
      filter: /\bsort:((owner|updated)-(asc|desc))/.freeze,
      multi: false
    },
    status: {
      filter: /\bstatus:(\S+)/.freeze,
      multi: false,
    },
  }

  #
  # Controller & View Helpers
  #

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def current_business
    @current_business ||= begin
      business = find_business
      return business if business || !T.unsafe(self).respond_to?(:current_organization)
      T.unsafe(self).current_organization&.business
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def business_saml_sso_enabled?
    !GitHub.single_business_environment? || GitHub.auth.saml?
  end

  def trial_expired_or_cancelled?
    current_business.trial_expired? || current_business.trial_cancelled?
  end

  def parse_query_string(query, filter_map: {})
    return {} if query.nil?

    query = GitHub::UTF8.scrubbed_unicode3(query)
    filters = filter_map.map do |key, options|
      # parse the query string for the given query filter
      filter_result = query.scan(options[:filter]).map do |match|
        value = match[0]
        next value unless options[:graphql_enum] || options[:enum]

        if options[:graphql_enum]
          next value if options[:graphql_enum].values.values.find { |enum| enum.value == value }
        end
        if options[:enum]
          next value if options[:enum].values.find { |allowed_value| allowed_value == value }
        end
        next
      end

      # remove all filter matches from the query string
      query = query.gsub(options[:filter], "")

      filter_result.compact!
      filter_result = filter_result.last unless options[:multi]
      { key => filter_result }
    end

    # merge the filter results with the query without any of the filters
    # query.split.join(" ") does a strip on all words, removing both
    # internal and external unnecessary whitespace
    filters.reduce({}, &:merge).merge(query: query.split.join(" "))
  end

  def business_user_avatar(user, size = 44, options = {})
    user = user.user if user.is_a?(BusinessUserAccount)
    avatar_for(user, size, options)
  end

  def current_user_can_manage_settings(business)
    business.owner?(T.unsafe(self).current_user) || T.unsafe(self).current_user.site_admin?
  end

  def member_role(organization_role)
    case organization_role.to_s
    when "direct_member"
      "Member"
    when "admin"
      "Owner"
    end
  end

  def enterprise_paths(path_type, query: nil)
    case path_type
    when :admins
      T.unsafe(self).enterprise_admins_path(T.unsafe(self).this_business, query: query)
    when :teams
      T.unsafe(self).enterprise_teams_path(T.unsafe(self).this_business, query: query)
    when :pending
      T.unsafe(self).enterprise_pending_members_path(T.unsafe(self).this_business, query: query)
    when :failed
      T.unsafe(self).enterprise_failed_invitations_path(T.unsafe(self).this_business, query: query)
    when :members
      T.unsafe(self).people_enterprise_path(T.unsafe(self).this_business, query: query)
    when :collaborators
      T.unsafe(self).enterprise_outside_collaborators_path(T.unsafe(self).this_business, query: query)
    end
  end

  # Private: Returns the appropriate host domain for a given environment
  #
  # Returns a String
  def enterprise_url_host
    return if GitHub.codespaces? || GitHub.multi_tenant_enterprise?
    GitHub.host_domain
  end

  # Private: Returns the appropriate service provider url for a given environment
  #
  # Returns a String
  def service_provider_url
    host = enterprise_url_host
    return T.unsafe(self).enterprise_url(T.unsafe(self).this_business, host: host) if host.present?
    T.unsafe(self).enterprise_url(T.unsafe(self).this_business)
  end

  def saml_consume_url
    T.unsafe(self).idm_saml_consume_enterprise_url(T.unsafe(self).this_business)
  end

  # Returns true if we are in GHES with SCIM enabled, or if the business passed is enterprise managed
  # Returns false otherwise
  def scim_managed_enterprise?(business)
    business&.enterprise_server_scim_enabled? ||
    business&.enterprise_managed_user_enabled?
  end

  def show_onboarding_experience?(business)
    return false if GitHub.single_business_environment?
    return false unless T.unsafe(self).logged_in?
    return false if T.unsafe(self).current_user.dismissed_business_notice?(BusinessesHelper::TRIAL_ONBOARDING_NOTICE_NAME, business_id: business.id) && !business.trial_expired?
    return false if T.unsafe(self).current_user.dismissed_business_notice?(BusinessesHelper::COPILOT_ONBOARDING_NOTICE_NAME, business_id: business.id)
    return true if business.seats_plan_basic?
    return false unless business.adminable_by?(T.unsafe(self).current_user)
    return true if business.trial? && !business.feature_enabled?(:digital_front_door_getting_started)

    false
  end

  def show_onboarding_experience_banner?(business)
    return false unless T.unsafe(self).logged_in?
    return false unless business.trial?

    !T.unsafe(self).current_user.dismissed_business_notice?("trial_onboarding_banner", business_id: business.id)
  end

  def show_trial_actions?(business)
    return false if T.unsafe(self).this_business.upgrading_from_organization?
    return false if T.unsafe(self).this_business.trial_converted?
    return false if T.unsafe(self).this_business.trial_conversion_initiated?
    T.unsafe(self).this_business.trial? || T.unsafe(self).this_business.trial_cancelled?
  end

  # Public: Returns the current trial status of the business whether it is
  # 1) Active with number of remaining days on trial
  # 2) Expired
  # 3) Conversion initiated with date and time of initiation
  # 4) Converted
  # 5) Cancelled
  def trial_status(business)
    if business.trial? && !business.trial_expired? && !business.trial_conversion_initiated?
      "Active with #{pluralize(business.trial_days_remaining, "day")} remaining"
    elsif business.trial_expired?
      "Expired"
    elsif business.trial_conversion_initiated?
      "Conversion initiated on #{business.trial_conversion_initiated_at}"
    elsif business.trial_converted?
      "Converted"
    elsif business.trial_cancelled?
      "Cancelled"
    end
  end

  # Public: Returns the current upgrade from organization status of the business
  # 1) Upgrade initiated
  # 2) Upgrade payment in progress
  # 3) Upgrade completed
  # 4) Directly upgraded without payment
  def upgrade_status(business)
    return nil if business.trial?
    if business.organization_upgrade_initiated?
      "Organization upgrade initiated"
    elsif business.organization_upgrade_purchase_initiated?
      "Organization upgrade purchase in progress"
    elsif (business.upgraded_at && business.no_trial_or_active_trial?) || business.organization_upgrade_completed?
      "Organization upgrade completed"
    elsif business.organization_direct_upgraded?
      "Directly upgraded from a GHEC org"
    elsif business.creation_initiated_from_coupon?
      "Creation initiated from coupon redemption"
    elsif business.creation_from_coupon_purchase_initiated?
      "Payment in progress following coupon redemption"
    elsif business.created_from_coupon?
      "Created from coupon"
    end
  end

  def show_org_upgrade_onboarding_experience?(business)
    return false unless T.unsafe(self).logged_in?
    return false unless business.upgraded_from_organization?
    return false if business.downgraded_to_free_plan?
    business.org_upgrade_onboarding_notice_set?(T.unsafe(self).current_user) && !T.unsafe(self).current_user.dismissed_business_notice?("org_upgrade_onboarding", business_id: business.id)
  end

  def buy_enterprise_flavor(short: false)
    if current_business&.metered_plan?
      return short ? "Activate paid Enterprise" : "Activate paid GitHub Enterprise"
    end
    short ? "Buy Enterprise" : "Buy GitHub Enterprise"
  end

  def buying_enterprise_flavor
    return "activating your Enterprise" if current_business&.metered_plan?
    "buying GitHub Enterprise"
  end

  def show_unaffiliated_members?(business)
    business.supports_unaffiliated_user_accounts?
  end

  # Check whether the copilot licensing is enabled at enterprise level for enterprise team group mappings.
  # Not to be confused with the copilot licensing enabled at organization level.
  #
  # business - The Business.
  #
  # Returns Boolean.
  def enterprise_copilot_licensing_enabled?(business)
    business.copilot_licensing_enabled?
  end

  ##
  # Summary: Check whether the enterprise teams are enabled for this business.
  #
  # business - The Business.
  #
  # Returns Boolean.
  def enterprise_teams_enabled?(business)
    business && business.enterprise_teams_enabled?
  end

  private

  def find_business
    Business.find_by(slug: slug_param)
  end

  def slug_param
    T.unsafe(self).params[:slug]
  end

  # Extracts the parameters coming from a "Test SAML settings" flow,
  # mixing them with the existing controller parameters
  #
  # Returns an ActionController::Parameters hash that includes the
  # existing controller #params and test-related keys used by
  # Businesses::Settings::SecurityView if a test was performed,
  # otherwise just the current #params. params if no test was performed.
  def params_for_saml_test_result
    extra_params = {}
    if T.unsafe(self).flash[:saml_test_result]
      test_settings = Business::SamlProviderTestSettings.most_recent_for(
        user: T.unsafe(self).current_user,
        business: T.unsafe(self).this_business,
        result: T.unsafe(self).flash[:saml_test_result],
      )
      if test_settings
        ActiveRecord::Base.connected_to(role: :writing) do
          test_settings.save!
        end
        extra_params[:test_settings] = "1"
        if test_settings.success?
          extra_params[:saml_testing] = { success: true }
        else
          extra_params[:saml_testing] = { failure: true }
          extra_params[:saml_testing][:message] = test_settings.message
        end

        extra_params[:saml] = {
          sso_url: test_settings.sso_url,
          issuer: test_settings.issuer,
          idp_certificate: test_settings.idp_certificate,
          signature_method: test_settings.signature_method,
          digest_method: test_settings.digest_method,
        }
      end
    end
    extra_params[:current_external_identity] = T.unsafe(self).current_external_identity(target: T.unsafe(self).this_business)

    T.unsafe(self).params.merge extra_params
  end

  def enterprise_all_members_count
    return @enterprise_all_members_count if defined?(@enterprise_all_members_count)
    @enterprise_all_members_count = current_business.filtered_members(T.unsafe(self).current_user).count
  end

  def enterprise_org_members_count
    return @enterprise_org_members_count if defined? @enterprise_org_members_count
    @enterprise_org_members_count = current_business.filtered_members(T.unsafe(self).current_user, role: "member").count
  end

  def enterprise_org_owners_count
    return @enterprise_org_owners_count if defined? @enterprise_org_owners_count
    @enterprise_org_owners_count = current_business.filtered_members(T.unsafe(self).current_user, role: "owner").count
  end

  def enterprise_owner_count
    return @enterprise_owner_count if defined? @enterprise_owner_count
    @enterprise_owner_count = current_business.admins(role: Business::OWNER_ROLE).count
  end

  def enterprise_billing_manager_count
    return @enterprise_billing_manager_count if defined? @enterprise_billing_manager_count
    @enterprise_billing_manager_count = current_business.admins(role: Business::BILLING_MANAGER_ROLE).count
  end

  def outside_collaborators_count(business)
    return @outside_collaborators_count if defined? @outside_collaborators_count
    @outside_collaborators_count = business.outside_collaborators.count
  end

  def guest_collaborators_count
    return @guest_collaborators_count if defined? @guest_collaborators_count
    @guest_collaborators_count = current_business.filtered_members(T.unsafe(self).current_user, role: "guest_collaborator").count
  end

  def unaffiliated_users_count
    return @unaffiliated_users_count if defined? @unaffiliated_users_count
    @unaffiliated_users_count = current_business.filtered_members(T.unsafe(self).current_user, role: "unaffiliated").count
  end

  def ghec_user_ids
    return @ghec_user_ids if defined? @ghec_user_ids
    @ghec_user_ids = current_business.filtered_members(
      T.unsafe(self).current_user,
      deployment: T.must(Platform::Enums::EnterpriseUserDeployment.values["CLOUD"]).value
    ).pluck(:id)
  end

  def ghes_user_ids
    return @ghes_user_ids if defined? @ghes_user_ids
    @ghes_user_ids = current_business.filtered_members(
      T.unsafe(self).current_user,
      deployment: T.must(Platform::Enums::EnterpriseUserDeployment.values["SERVER"]).value
    ).pluck(:id)
  end

  def total_consumed_licenses_count
    return @total_consumed_licenses_count if defined? @total_consumed_licenses_count
    @total_consumed_licenses_count = current_business.total_consumed_licenses
  end

  def total_purchased_licenses_count
    return @total_purchased_licenses_count if defined? @total_purchased_licenses_count
    @total_purchased_licenses_count = current_business.total_purchased_licenses_with_overages
  end

  def consumed_enterprise_licenses_count
    return @consumed_enterprise_licenses_count if defined? @consumed_enterprise_licenses_count
    @consumed_enterprise_licenses_count = current_business.consumed_enterprise_licenses
  end

  def purchased_enterprise_licenses_count
    return @purchased_enterprise_licenses_count if defined? @purchased_enterprise_licenses_count
    @purchased_enterprise_licenses_count = current_business.purchased_enterprise_licenses
  end

  def consumed_volume_licenses_count
    return @consumed_volume_licenses_count if defined? @consumed_volume_licenses_count
    @consumed_volume_licenses_count = current_business.consumed_volume_licenses
  end

  def purchased_volume_licenses_count
    return @purchased_volume_licenses_count if defined? @purchased_volume_licenses_count
    @purchased_volume_licenses_count = current_business.purchased_volume_licenses_with_overages
  end

  def consumed_users_access_licenses_count
    return @consumed_users_access_licenses_count if defined? @consumed_users_access_licenses_count
    @consumed_users_access_licenses_count = current_business.consumed_users_access_licenses
  end

  def consumed_pending_invitation_licenses_count
    return @consumed_pending_invitation_licenses_count if defined? @consumed_pending_invitation_licenses_count
    @consumed_pending_invitation_licenses_count = current_business.consumed_pending_invitation_licenses
  end

  def consumed_copilot_licenses_count
    return @consumed_copilot_licenses_count if defined? @consumed_copilot_licenses_count
    @consumed_copilot_licenses_count = Copilot::Businesses::SeatManagement.copilot_standalone_seat_count(current_business)
  end

  # Private: The default plan duration selected when upgrading a trial business
  # or changing the plan duration of a non-trial business.
  #
  # business - The Business.
  #
  # Returns a String.
  def default_plan_duration(business)
    return User::BillingDependency::MONTHLY_PLAN if business.trial? || business.organization_upgrade_initiated?
    business.plan_duration
  end
end
