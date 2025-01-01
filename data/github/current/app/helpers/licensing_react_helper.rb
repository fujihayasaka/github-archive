# typed: strict
# frozen_string_literal: true

module LicensingReactHelper
  extend T::Helpers
  include BillingSettingsHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::NumberHelper
  include UrlHelper

  FALLBACK_GHE_UNIT_PRICE = 21.0

  sig { params(billable_entity: T.any(Business, Organization)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def payment_method_react_payload(billable_entity)
    return unless billable_entity.payment_method

    payment_method = billable_entity.payment_method
    {
      credit_card: payment_method.credit_card?,
      paypal: payment_method.paypal?,
      last_four: payment_method.last_four,
      card_type: payment_method.card_type,
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_trial_react_payload(business)
    return nil unless business.trial?

    {
      expirationDate: GitHub::Billing.date_in_timezone(business.trial_expires_at.to_date).as_json,
      isActive: !business.trial_expired?,
      trialLicensesAllowed: business.purchased_enterprise_licenses,
    }
  end

  sig { params(business: Business).returns(T::Boolean) }
  def expired_ghas_trial?(business)
    business.advanced_security_free_trial_expired? &&
    business.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF &&
    Billing::Public::SubscriptionItem.trial_exists?(
      product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
      account: business,
      within: (business.advanced_security_trial_number_of_days).days.ago
    ).value { false }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghas_trial_react_payload(business)
    return nil unless business.has_active_advanced_security_trial? || expired_ghas_trial?(business)

    expiration_date = if business.advanced_security_free_trial_ends_on.present?
      GitHub::Billing.date_in_timezone(T.must(business.advanced_security_free_trial_ends_on))
    else
      nil
    end

    {
      expirationDate: expiration_date&.as_json,
      isActive: expiration_date.present? ? expiration_date >= GitHub::Billing.today : false,
    }
  end

  sig { params(business: Business, viewer: User).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghas_self_serve_trial_react_payload(business, viewer)
    return nil unless business.eligible_for_self_serve_advanced_security_trial? || expired_ghas_trial?(business)

    {
      organizationToOnboard: business.organization_for_advanced_security_trial(actor: viewer)&.to_param,
      showNoOrgsWarning: business.filtered_organizations(viewer:).empty?,
      trialDays: business.new_advanced_security_trial_days,
      trialExpired: expired_ghas_trial?(business),
    }
  end

  sig { params(business: Business, product: Symbol).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def invoice_license_react_payload(business:, product:)
    return nil unless business.invoiced?
    return nil unless business.sales_managed_subscription_self_serve_eligible?
    return nil if business.past_due_invoice?

    payload = {}
    payload[:actionType] = :upgrade if business.eligible_for_upgrade?
    payload[:actionType] = :renewal if business.eligible_for_renewal?

    status_message = if product == :ghec
      enterprise_status_inline_message(business: business)
    elsif product == :ghas
      ghas_status_inline_message(business: business)
    end
    renewal_datetime = business.renewal_scheduled_start_datetime
    payload.merge({
      expired: business.billing_term_ends_on < GitHub::Billing.today,
      renewalScheduledStartDate: renewal_datetime&.iso8601,
      hasFutureRenewal: renewal_datetime ? GitHub::Billing.future?(renewal_datetime.to_datetime) : false,
      isGHERenewal: business.ghe_renewal?,
      isGHASRenewal: business.ghas_renewal?,
      statusMessage: status_message,
    })
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self_serve_ghas_subscription_payload(business)
    return nil unless business.has_self_serve_advanced_security?

    {
      expiration: business.advanced_security_subscription_item&.next_billing_date&.in_time_zone(GitHub::Billing.timezone).as_json,
      pendingCycleChange: ghas_pending_plan_change_payload(business),
    }
  end

  class StatusMessage < T::Struct
    class Variants < T::Enum
      enums do
        Success = new
        Critical = new
      end
    end

    const :variant, Variants
    const :text, String
  end

  sig { params(business: Business).returns(T.nilable(StatusMessage)) }
  def enterprise_status_inline_message(business:)
    if business.has_any_failed_ghe_change_requests?
      return StatusMessage.new(
        variant: StatusMessage::Variants::Critical,
        text: "Your Enterprise Cloud licenses upgrade failed, please contact sales.",
      )
    end

    if business.has_any_pending_ghe_change_requests?
      if business.ghe_update_seat_quantity&.positive?
        return StatusMessage.new(
          variant: StatusMessage::Variants::Success,
          text: "Your upgrade of #{pluralize(business.ghe_update_seat_quantity, 'Enterprise Cloud license')} is being processed.",
        )
      end

      return StatusMessage.new(
        variant: StatusMessage::Variants::Success,
        text: "Your Enterprise Cloud upgrade is being processed.",
      )
    end

    nil
  end

  sig { params(organization: Organization, preopen_seat_management: T.nilable(T::Boolean)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def teams_ghas_overview_react_payload(organization:, preopen_seat_management: false)
    license = organization.advanced_security_license
    is_bundled_license = organization.ghas_sku_purchased_for_entity?
    is_metered_licensed = organization.advanced_security_products_metered?

    billable_entity = organization
    billing_cycle = determine_billing_cycle(
      billable_entity:,
      is_bundled_license:,
      is_metered_licensed:
    )

    skus = calculate_skus_with_pricing(
      billable_entity:,
      is_bundled_license:,
      is_metered_licensed:,
      license:
    )

    # Calculate total billable licenses
    billable_licenses_val = skus.sum { |sku| sku[:billableLicenses] }

    # Calculate total current payment
    total_payment = skus.sum { |sku| sku[:billableAmount] }

    # Apply yearly multiplication if needed for display
    if !is_metered_licensed && billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year
      total_payment *= 12
    end

    billing_term_end_date = organization.billed_on&.in_time_zone(GitHub::Billing.timezone).as_json || GitHub::Billing.today.in_time_zone(GitHub::Billing.timezone).as_json

    {
      billingCycle: "#{billing_cycle.serialize.titleize}ly",
      billableLicenses: billable_licenses_val,
      billingTermEndDate: billing_term_end_date,
      configureButtonPath: "/organizations/#{organization.name}/settings/security_products",
      currentPayment: Billing::Money.new(total_payment * 100).format,
      ghasFeaturesUrl: "#{GitHub.url}/features/security",
      isAdvancedSecurityEnabled: organization.advanced_security_purchased?,
      isBundled: is_bundled_license,
      isManagingSeats: false,
      isMeteredLicensed: true,
      isSelfServeAdvancedSecurity: false,
      paymentMethod: payment_method_react_payload(organization),
      selfServeSubscriptionInfo: nil,
      skus:,
      unlimitedLicense: true,
    }
  end

  sig { params(business: Business).returns(T.nilable(StatusMessage)) }
  def ghas_status_inline_message(business:)
    if business.has_any_failed_ghas_change_requests?
      return StatusMessage.new(
        variant: StatusMessage::Variants::Critical,
        text: "Your Advanced Security licenses upgrade failed, please contact sales.",
      )
    end

    if business.ghas_update?
      if business.ghas_update_seat_quantity_difference&.positive?
        return StatusMessage.new(
          variant: StatusMessage::Variants::Success,
          text: "Your upgrade of #{pluralize(business.ghas_update_seat_quantity_difference, 'Advanced Security license')} is being processed.",
        )
      end

      return StatusMessage.new(
        variant: StatusMessage::Variants::Success,
        text: "Your Advanced Security upgrade is being processed.",
      )
    end
    nil
  end

  sig { params(business: Business).returns(String) }
  def buy_ghas_button_path(business)
    if business.eligible_for_self_serve_advanced_security?(skip_shared_checks: true) && business.eligible_for_self_serve_payment?
      return Rails.application.routes.url_helpers.billing_settings_advanced_security_upgrade_enterprise_path(business)
    end

    ""
  end

  sig { params(business: Business, viewer: User, preopen_seat_management: T.nilable(T::Boolean)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghas_overview_react_payload(business:, viewer:, preopen_seat_management: false)
    license = business.advanced_security_license
    is_bundled_license = business.ghas_sku_purchased_for_entity?
    is_metered_licensed = business.advanced_security_products_metered?
    billable_entity = business
    is_unlimited_license = license.unlimited_seats?

    billing_cycle = determine_billing_cycle(
      billable_entity:,
      is_bundled_license:,
      is_metered_licensed:
    )

    trial_info = ghas_trial_react_payload(business)

    skus = calculate_skus_with_pricing(
      billable_entity:,
      is_bundled_license:,
      is_metered_licensed:,
      license:,
    )
    # If the business is on a trial they will have a soft cap of available licenses based on either:
    # 1. The number of licenses purchased for the business (aka GHE)
    # 2. The number of licenses purchased for the specific GHAS sku
    # Therefore we override the purchasedLicenses value if they will be on the unlimited license which sets licenses to 0
    if trial_info.present? && trial_info[:isActive]
      skus.map do |sku|
        if sku[:purchasedLicenses].zero? || sku[:unlimitedLicense]
          sku[:purchasedLicenses] = business.purchased_enterprise_licenses
        end
        # Bundled metered trials are created with 1 purchased seat but are treated as unlimited; see AdvancedSecurity::Public::Subscription#subscribe_to_advanced_security_trial
        # To avoid confusion for customer, don't display the 1 purchased license while on a trial
        if sku[:unlimitedLicense]
          sku[:billableLicenses] = 0
          sku[:billableAmount] = 0
        end
      end
    end

    # Calculate total billable licenses
    billable_licenses_val = skus.sum { |sku| sku[:billableLicenses] }

    # Calculate total current payment
    total_payment = skus.sum { |sku| sku[:billableAmount] }

    # Apply yearly multiplication if needed for display
    if !is_metered_licensed && billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year
      total_payment *= 12
    end

    {
      billingCycle: "#{billing_cycle.serialize.titleize}ly",
      billableLicenses: billable_licenses_val,
      billingTermEndDate: business.next_ghas_payment_due.as_json,
      buyButtonPath: buy_ghas_button_path(business),
      currentPayment: Billing::Money.new(total_payment * 100).format,
      eligibleForTrial: business.eligible_for_self_serve_advanced_security_trial?,
      ghasFeaturesUrl: "#{GitHub.url}/features/security",
      invoiceLicenseInfo: invoice_license_react_payload(business: business, product: :ghas),
      isAdvancedSecurityEnabled: business.advanced_security_purchased?,
      isBundled: is_bundled_license,
      isManagingSeats: preopen_seat_management && business.has_self_serve_advanced_security?,
      isMeteredLicensed: is_metered_licensed,
      isSelfServeAdvancedSecurity: business.has_self_serve_advanced_security?,
      paymentMethod: payment_method_react_payload(business),
      selfServeSubscriptionInfo: self_serve_ghas_subscription_payload(business),
      selfServeTrialInfo: ghas_self_serve_trial_react_payload(business, viewer),
      skus:,
      trialInfo: trial_info,
      unlimitedLicense: is_unlimited_license,
      usageExceededMessage: allowance_exceeded_banner_message(
        business:,
        is_bundled_license:,
        is_metered_licensed:,
        is_unlimited_license:,
        skus:
      ),
      usageAtCapacityMessage: usage_at_capacity_banner_message(
        business:,
        is_bundled_license:,
        is_metered_licensed:,
        is_unlimited_license:,
        skus:
      )
    }
  end

  sig { params(business: Business).returns(T::Hash[Symbol, T.untyped]) }
  def ghe_common_react_payload(business)
    roles = admin_roles(business)
    is_metered_licensed = business.metered_plan?
    is_licensify = business.licensing_platform == Business::LicenseDependency::LicensingPlatform::Licensify

    ghe_billable = if is_metered_licensed
      counts = business.license_attributer.license_counts
      counts[:ghe_active_cloud_user_count] + counts[:ghe_deactivated_cloud_user_count] + counts[:ghe_suspended_cloud_user_count]
    else
      business.purchased_enterprise_licenses
    end

    ghe_consumed = if is_metered_licensed
      business.license_attributer.license_counts[:ghe_active_cloud_user_count]
    else
      business.consumed_enterprise_licenses
    end

    manage_seats = Business::ManageSeats.new(business: business, new_seats: nil)
    current_payment = if is_metered_licensed && ghe_consumed == 0
      Billing::Money.new(0).format
    elsif is_metered_licensed && is_licensify
      Business::ManageSeats.new(business: business, new_seats: ghe_billable).new_payment
    else
      manage_seats.current_payment
    end

    {
      billingTermEndDate: business.next_sdlc_payment_due.as_json,
      currentPayment: current_payment,
      enterpriseLicensesBillable: ghe_billable,
      enterpriseLicensesConsumed: ghe_consumed,
      enterpriseLicensesPurchased: business.purchased_enterprise_licenses,
      invoiceLicenseInfo: invoice_license_react_payload(business: business, product: :ghec),
      isMonthly: business.plan_duration == User::BillingDependency::MONTHLY_PLAN,
      isVolumeLicensed: !is_metered_licensed,
      isVssEnabled: business.has_active_vss_bundle?,
      trialInfo: ghe_trial_react_payload(business),
      unitCost: manage_seats.seat_cost_label_short,
      vssLicensesConsumed: business.consumed_volume_licenses,
      vssLicensesPurchasedWithOverage: business.purchased_volume_licenses_with_overages,
      canViewMembers: roles.include?("owner")
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_details_react_payload(business:)
    ghe_common_react_payload(business)
  end

  sig { params(business: Business, preopen_seat_management: T.nilable(T::Boolean)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_overview_react_payload(business:, preopen_seat_management: false)
    payload = ghe_common_react_payload(business)
    is_self_serve = business.eligible_for_self_serve_payment?
    is_self_serve_blocked = !is_self_serve || business.downgraded_to_free_plan? || business.dunning? || business.enterprise_managed?
    pending_cycle_change = is_self_serve_blocked ? nil : pending_cycle_seat_change_payload(business)
    current_user = T.cast(T.unsafe(self).current_user, User)

    payload.merge(
      canManageDetails: current_user.feature_enabled?(:licensing_vss_management) && payload[:canViewMembers] && business.has_active_vss_bundle?,
      isManagingSeats: preopen_seat_management && !business.metered_plan? && is_self_serve && !is_self_serve_blocked,
      isSelfServe: is_self_serve,
      isSelfServeBlocked: is_self_serve_blocked,
      paymentMethod: payment_method_react_payload(business),
      pendingCycleChange: pending_cycle_change
    )
  end

  sig do
    params(
      business: Business,
      search: T.nilable(String),
      page: Integer,
      per_page: Integer,
      vs_filter: String
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def ghe_licensee_list_page_payload(business:, search:, page:, per_page:, vs_filter: "all")
    current_user = T.cast(T.unsafe(self).current_user, User)

    # Get members, including filtering by search string
    members = business.filtered_members(
      current_user,
      query: search || "",
      deployment: "cloud", # exclude server-only users
      include_unaffiliated: false # exclude unaffiliated users
    )

    # Prepare what we need to distinguish license types
    vss_license_user_ids = T.let(
      business.license_attributer.bundled_license_assignment_user_ids || [],
      T::Array[Integer]
    ).to_set
    all_license_user_ids = business.license_attributer.user_ids
    non_vss_license_user_ids = all_license_user_ids - vss_license_user_ids

    # Map each member with all needed info before additional filtering and sorting
    licensees = members.map do |m|
      user = m.is_a?(BusinessUserAccount) ? m.user : m
      user_id = user&.id
      license_type = if vss_license_user_ids.include?(user_id)
        "Visual Studio"
      elsif non_vss_license_user_ids.include?(user_id)
        "Enterprise"
      else
        "Unlicensed"
      end

      {
        member: m,
        user: user,
        user_id: user_id,
        license_type: license_type,
        login: user&.display_login,
        name: user&.name,
        avatar_url: user&.primary_avatar_url,
        access_type: business.owner?(user) ? "Admin" : "Member"
      }
    end

    # Apply visual studio filter
    case vs_filter
    when "manually-matched"
      licensees = [] # there are no manually matched users yet
    when "automatically-matched"
      licensees.select! { |info| info[:license_type] == "Visual Studio" }
    when "unmatched"
      licensees.select! { |info| info[:license_type] == "Enterprise" }
    when "all"
      # exclude 'Unlicensed' users
      licensees.select! { |info| info[:license_type] == "Visual Studio" || info[:license_type] == "Enterprise" }
    end

    # Sort by login (case-insensitive)
    licensees.sort_by! { |info| info[:login] ? info[:login].downcase : "" }

    # Apply pagination
    total_pages = (licensees.size.to_f / per_page).ceil
    paged_infos = licensees.slice((page - 1) * per_page, per_page) || []

    {
      licensees: paged_infos.map do |info|
        {
          id: info[:user_id],
          accessType: info[:access_type],
          avatarUrl: info[:avatar_url],
          fullName: info[:name],
          license: info[:license_type],
          login: info[:login]
        }
      end,
      page: page,
      totalPages: total_pages
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghes_overview_react_payload(business:)
    bundled_ghas_license_count = 0
    bundled_ghas_billable_license_count = 0
    code_security_license_count = 0
    code_security_billable_license_count = 0
    secret_protection_license_count = 0
    secret_protection_billable_license_count = 0

    if business.advanced_security_products_bundled?
      bundled_counts = server_only_ghas_license_counts(business:, sku: GitHub::Turboghas::SKU::Bundled)
      bundled_ghas_license_count = bundled_counts[:consumed_license_count] || 0
      bundled_ghas_billable_license_count = bundled_counts[:billable_license_count] || 0
    else
      code_security_counts = server_only_ghas_license_counts(business:, sku: GitHub::Turboghas::SKU::CodeSecurity)
      code_security_license_count = code_security_counts[:consumed_license_count] || 0
      code_security_billable_license_count = code_security_counts[:billable_license_count] || 0

      secret_protection_counts = server_only_ghas_license_counts(business:, sku: GitHub::Turboghas::SKU::SecretSecurity)
      secret_protection_license_count = secret_protection_counts[:consumed_license_count] || 0
      secret_protection_billable_license_count = secret_protection_counts[:billable_license_count] || 0
    end

    manage_seats = Business::ManageSeats.new(business: business, new_seats: nil)
    has_enterprise_server = business.enterprise_installations.any?

    ghes_license_count = 0
    ghes_billable_license_count = 0
    has_metered_ghe = business.metered_plan?
    if has_metered_ghe
      counts = business.license_attributer.license_counts
      ghes_license_count = counts[:ghe_active_server_only_user_count]
      ghes_billable_license_count = counts[:ghe_active_server_only_user_count] + counts[:ghe_deactivated_server_only_user_count] + counts[:ghe_suspended_server_only_user_count]
    end

    ghes_unit_price = manage_seats.seat_change&.unit_price&.to_f || FALLBACK_GHE_UNIT_PRICE
    bundled_ghas_unit_price = business.advanced_security_price_for_sku(sku: "ghas_licenses", seats: 1).to_f
    code_security_unit_price = business.advanced_security_price_for_sku(sku: "ghas_code_security_licenses", seats: 1).to_f
    secret_protection_unit_price = business.advanced_security_price_for_sku(sku: "ghas_secret_protection_licenses", seats: 1).to_f

    {
      dueDate: business.next_sdlc_payment_due.as_json,
      hasEnterpriseServer: has_enterprise_server,
      hasMeteredGhe: has_metered_ghe,
      ghesLicenseCount: ghes_license_count,
      ghesBillableLicenseCount: ghes_billable_license_count,
      bundledGhasLicenseCount: bundled_ghas_license_count,
      bundledGhasBillableLicenseCount: bundled_ghas_billable_license_count,
      codeSecurityLicenseCount: code_security_license_count,
      codeSecurityBillableLicenseCount: code_security_billable_license_count,
      secretProtectionLicenseCount: secret_protection_license_count,
      secretProtectionBillableLicenseCount: secret_protection_billable_license_count,
      ghesUnitPrice: ghes_unit_price,
      bundledGhasUnitPrice: bundled_ghas_unit_price,
      codeSecurityUnitPrice: code_security_unit_price,
      secretProtectionUnitPrice: secret_protection_unit_price,
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_overview_react_payload(business:)
    copilot_toc_link = Copilot::COPILOT_SPECIFIC_TERMS
    cfb_help_link = Copilot::COPILOT_FOR_BUSINESS_DOCUMENTATION
    cfe_help_link = Copilot::COPILOT_FOR_ENTERPRISE_DOCUMENTATION
    copilot_business = Copilot::Business.new(business)
    copilot_enabled = copilot_business.copilot_enabled?
    copilot_can_be_reenabled = !copilot_enabled && Copilot::SeatAssignment.for_business(business).present?
    business_slug = business.slug
    {
      isCopilotEnabled: copilot_enabled,
      copilotCanBeReenabled: copilot_can_be_reenabled,
      businessSlug: business_slug,
      copilotTocLink: copilot_toc_link,
      cfbHelpLink: cfb_help_link,
      cfeHelpLink: cfe_help_link,
    }.merge(copilot_licensing_information(business))
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_details_react_payload(business:)
    copilot_business = Copilot::Business.new(business)
    enablement_setting = copilot_business.copilot_business_enablement_setting
    enabled_organization_count = copilot_business.copilot_enabled_organizations_count
    enabled_user_count = Copilot::SeatAssignment.where(owner_id: business.id).count
    {
      enablementSetting: enablement_setting,
      enabledOrganizationCount: enabled_organization_count,
      enabledUserCount: enabled_user_count,
    }
    .merge(copilot_licensing_information(business))
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_organization_react_payload(business:)
    orgs_with_copilot_access = []
    orgs_without_copilot_access = []

    organizations = business.organizations
    organizations.each do |organization|
      copilot_organization = Copilot::Organization.new(organization)
      license_count = Copilot::Seat.for_organization(organization).count
      copilot_plan = copilot_organization.copilot_plan.present? && copilot_organization.copilot_enabled? ? copilot_organization.copilot_plan : "disabled"
      copilot_can_be_reenabled = copilot_plan == "disabled" && Copilot::SeatAssignment.for_organization(organization).organization_assignments.any?
      expiration_date = copilot_organization.pending_plan_downgrade_date&.strftime("%Y-%m-%d")
      org_url = user_path(organization)
      avatar_url = organization.primary_avatar_url
      org = {
        login: organization.display_login,
        id: organization.id,
        licenseCount: license_count,
        copilotPlan: copilot_plan,
        copilotCanBeReenabled: copilot_can_be_reenabled,
        expirationDate: expiration_date,
        orgUrl: org_url,
        avatarUrl: avatar_url,
        newPlan: copilot_plan,
      }
      if copilot_can_be_reenabled || copilot_plan != "disabled"
        orgs_with_copilot_access << org
      else
        orgs_without_copilot_access << org
      end
    end

    {
      withCopilotAccess: orgs_with_copilot_access,
      withoutCopilotAccess: orgs_without_copilot_access,
    }
  end

  sig { params(business: Business).returns(T::Hash[Symbol, Integer]) }
  def copilot_users_react_payload(business:)
    current_user = T.cast(T.unsafe(self).current_user, User)

    # Gathers all the Copilot seats for the business for all members
    all_copilot_seats = Copilot::Seat.for_business(business)
    seats_by_user = all_copilot_seats.group_by(&:assigned_user_id)

    # Only grab the users that have Copilot seats assigned to them directly from the business
    business_owned_seats = all_copilot_seats.select { |seat| seat.owner_id == business.id && seat.owner_type == "Business" }
    user_ids_with_business_seats = business_owned_seats.map(&:assigned_user_id).compact.uniq

    return { withCopilotAccess: [] } if user_ids_with_business_seats.empty?

    users = User.where(id: user_ids_with_business_seats)
    users_with_copilot_access = users.map do |user|
      # Here we want to collect all seats assigned to the user in the business context, including those from orgs
      user_seats = seats_by_user[user.id] || []
      next if user_seats.empty?

      user_url = user_path(user)
      avatar_url = user.primary_avatar_url
      plan_types = Copilot::Seat.seat_plan_types_by_owner_type(user_seats)
      licenses = get_all_copilot_license_info_from_user_seats(user_seats, plan_types, business)
      dominant_license = get_dominant_license_from_user_seats(user_seats, plan_types)

      user = {
        login: user.display_login,
        name: user.safe_profile_name,
        id: user.id,
        userUrl: user_url,
        avatarUrl: avatar_url,
        licenses: licenses,
        dominantLicense: dominant_license,
      }
    end.compact

    {
      withCopilotAccess: users_with_copilot_access,
    }
  end

  private

  sig { params(seats: T::Array[Copilot::Seat], plan_types: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def get_dominant_license_from_user_seats(seats, plan_types)
    return {} if seats.nil?
    seats.sort_by do |seat|
      Copilot::Seat.priority_for_copilot_sku(seat.copilot_sku)
    end

    dominant_license = seats.first
    return {} if dominant_license.nil?

    plan_type = plan_types.dig(dominant_license.seat_assignment&.id, :plan) # Get the plan type for the seat
    owner_type = dominant_license.owner.is_a?(Business) ? "business" : "organization"
    owner_name = dominant_license.owner.name
    owner_id = dominant_license.owner.id

    {
      ownerType: owner_type,
      ownerName: owner_name,
      ownerId: owner_id,
      expirationDate: dominant_license.pending_cancellation_date,
      planType: plan_type,
    }
  end

  sig { params(seats: T::Array[Copilot::Seat], plan_types: T::Hash[T.untyped, T.untyped], business: Business).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_all_copilot_license_info_from_user_seats(seats, plan_types, business)
    licenses = []
    seats.each do |seat|
      plan_type = plan_types.dig(seat.seat_assignment&.id, :plan) # Get the plan type for the seat
      owner_type = seat.owner.is_a?(Business) ? "business" : "organization"
      owner_name = seat.owner.name
      owner_id = seat.owner.id
      license = {
        ownerType: owner_type,
        ownerName: owner_name,
        ownerId: owner_id,
        expirationDate: seat.pending_cancellation_date,
        planType: plan_type,
      }
      licenses << license
    end

    licenses
  end

  sig { params(business: Business, sku: GitHub::Turboghas::SKU).returns(T::Hash[Symbol, Integer]) }
  def server_only_ghas_license_counts(business:, sku:)
    ghes_committers = business.advanced_security_license_for_sku(sku:).ghes_committers
    unmatched = Set.new(ghes_committers&.unmatched || [])
    consumed_license_count = unmatched.size

    if business.metered_ghes_eligible?
      previous_unmatched = MeteredAdvancedSecurityScheduledEmitterJob::BusinessEmitterJob.unmatched_ids(sku: sku, business: business)
      if previous_unmatched
        unmatched.merge(previous_unmatched)
      end

      billable_license_count = unmatched.size
    else
      billable_license_count = 0
    end
    {
      consumed_license_count:,
      billable_license_count:,
    }
  end

  sig do
    params(
      business: Business
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def copilot_licensing_information(business)
    copilot_business = Copilot::Business.new(business)
    cfb_unit_price = Copilot::COPILOT_BUSINESS_MONTHLY_BASE_PRICE
    cfe_unit_price = Copilot::COPILOT_ENTERPRISE_MONTHLY_BASE_PRICE
    seat_counts_by_license = copilot_business.copilot_enabled_members_count_by_license
    consumed_business_licenses = seat_counts_by_license[:business].to_i
    consumed_enterprise_licenses = seat_counts_by_license[:enterprise].to_i
    total_cost = copilot_business.total_cost
    billing_term_end_date = business.billing_term_ends_on&.in_time_zone(GitHub::Billing.timezone).strftime("%B %-d, %Y")
    {
      skus: [
        {
          sku: Copilot::SKUIsolation::BUSINESS,
          consumedLicenses: consumed_business_licenses,
          unitPrice: cfb_unit_price,
        },
        {
          sku: Copilot::SKUIsolation::ENTERPRISE,
          consumedLicenses: consumed_enterprise_licenses,
          unitPrice: cfe_unit_price,
        }
      ],
      billingTermEndDate: billing_term_end_date,
      totalCost: total_cost
    }
  end

  sig do
    params(
      billable_entity: T.untyped,
      is_bundled_license: T::Boolean,
      is_metered_licensed: T::Boolean,
      license: ::AdvancedSecurityLicense,
    ).returns(T::Hash[Symbol, Integer])
  end
  def calculate_billable_licenses(billable_entity:, is_bundled_license:, is_metered_licensed:, license:)
    case [is_metered_licensed, is_bundled_license]
    when [true, true]
      { bundled: billable_entity.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled) }
    when [true, false]
      {
        secret_scanning: billable_entity.secret_protection_purchased? ? billable_entity.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::SecretSecurity) : 0,
        code_security: billable_entity.code_security_purchased? ? billable_entity.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::CodeSecurity) : 0
      }
    when [false, true]
      { bundled: license.seats }
    when [false, false]
      {
        secret_scanning: billable_entity.secret_protection_purchased? ? billable_entity.secret_scanning_license_count : 0,
        code_security: billable_entity.code_security_purchased? ? billable_entity.code_security_license_count : 0
      }
    else
      { bundled: 0 }
    end
  end

  sig { params(billable_entity: T.untyped, is_metered_licensed: T::Boolean, is_bundled_license: T::Boolean).returns(Billing::Public::SubscriptionItems::BillingCycle) }
  def determine_billing_cycle(billable_entity:, is_metered_licensed:, is_bundled_license:)
    if is_metered_licensed
      return Billing::Public::SubscriptionItems::BillingCycle::Month
    end

    # For volume bundled licenses, there is no support for an annual billing cycle
    if is_bundled_license && billable_entity.plan_duration == User::BillingDependency::YEARLY_PLAN
      Billing::Public::SubscriptionItems::BillingCycle::Month
    else
      # Use the default billing cycle for the business
      Billing::Public::SubscriptionItems::BillingCycle.from_serialized(billable_entity.plan_duration)
    end
  end

  sig do
    params(
      billable_entity: T.untyped,
      is_bundled_license: T::Boolean,
      is_metered_licensed: T::Boolean,
      license: ::AdvancedSecurityLicense,
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def calculate_skus_with_pricing(billable_entity:, is_bundled_license:, is_metered_licensed:, license:)
    skus = []
    billable_licenses = calculate_billable_licenses(
      billable_entity:,
      is_bundled_license:,
      is_metered_licensed:,
      license:
    )

    if is_bundled_license
      unit_price = billable_entity.advanced_security_unit_price(sku: "ghas_licenses")
      billable_license_count = T.must(billable_licenses[:bundled])
      server_only_consumed_licenses = 0
      if billable_entity.is_a?(Business)
        server_only_counts = server_only_ghas_license_counts(business: billable_entity, sku: GitHub::Turboghas::SKU::Bundled)
        server_only_consumed_licenses = server_only_counts[:consumed_license_count] || 0
      end

      skus << {
        sku: GitHub::Turboghas::SKU::Bundled.to_param,
        name: "Advanced Security",
        consumedLicenses: license.consumed_seats,
        purchasedLicenses: license.seats,
        unitPrice: unit_price.to_f,
        billableLicenses: billable_license_count,
        billableAmount: billable_entity.advanced_security_price_for_sku(
          sku: "ghas_licenses",
          seats: billable_license_count,
          unit_price: unit_price
        ).to_f,
        serverOnlyConsumedLicenses: server_only_consumed_licenses,
        unlimitedLicense: license.unlimited_seats?,
      }
    else
      if billable_entity.secret_protection_purchased?
        secret_scanning_unit_price = billable_entity.advanced_security_unit_price(sku: "ghas_secret_protection_licenses")
        secret_scanning_billable_licenses = T.must(billable_licenses[:secret_scanning])
        server_only_consumed_licenses = 0
        if billable_entity.is_a?(Business)
          server_only_counts = server_only_ghas_license_counts(business: billable_entity, sku: GitHub::Turboghas::SKU::SecretSecurity)
          server_only_consumed_licenses = server_only_counts[:consumed_license_count] || 0
        end

        skus << {
          sku: GitHub::Turboghas::SKU::SecretSecurity.to_param,
          name: "Secret Protection",
          consumedLicenses: billable_entity.secret_protection.seats_used,
          purchasedLicenses: billable_entity.secret_protection.seats,
          unitPrice: secret_scanning_unit_price.to_f,
          billableLicenses: secret_scanning_billable_licenses,
          billableAmount: billable_entity.advanced_security_price_for_sku(
            sku: "ghas_secret_protection_licenses",
            seats: secret_scanning_billable_licenses,
            unit_price: secret_scanning_unit_price
          ).to_f,
          serverOnlyConsumedLicenses: server_only_consumed_licenses,
          unlimitedLicense: billable_entity.secret_protection.unlimited_seats?,
        }
      end

      if billable_entity.code_security_purchased?
        code_security_unit_price = billable_entity.advanced_security_unit_price(sku: "ghas_code_security_licenses")
        code_security_billable_licenses = T.must(billable_licenses[:code_security])
        server_only_consumed_licenses = 0
        if billable_entity.is_a?(Business)
          server_only_counts = server_only_ghas_license_counts(business: billable_entity, sku: GitHub::Turboghas::SKU::CodeSecurity)
          server_only_consumed_licenses = server_only_counts[:consumed_license_count] || 0
        end

        skus << {
          sku: GitHub::Turboghas::SKU::CodeSecurity.to_param,
          name: "Code Security",
          consumedLicenses: billable_entity.code_security.seats_used,
          purchasedLicenses: billable_entity.code_security.seats,
          unitPrice: code_security_unit_price.to_f,
          billableLicenses: code_security_billable_licenses,
          billableAmount: billable_entity.advanced_security_price_for_sku(
            sku: "ghas_code_security_licenses",
            seats: code_security_billable_licenses,
            unit_price: code_security_unit_price
          ).to_f,
          serverOnlyConsumedLicenses: server_only_consumed_licenses,
          unlimitedLicense: billable_entity.code_security.unlimited_seats?,
        }
      end
    end

    skus
  end

  sig { params(sku: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(String)) }
  def format_exceeding_message(sku)
    return unless sku && sku[:consumedLicenses] > sku[:purchasedLicenses]

    "You are using #{pluralize(number_with_delimiter(sku[:consumedLicenses]), "#{sku[:name]} license")}, " \
      "exceeding the limit of #{number_with_delimiter(sku[:purchasedLicenses])}."
  end

  sig { params(sku: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(String)) }
  def format_at_capacity_message(sku)
    return unless sku && sku[:consumedLicenses] == sku[:purchasedLicenses]

    suffix = "license".pluralize(sku[:consumedLicenses])
    "You are at capacity for your #{sku[:name]} #{suffix}."
  end

  sig { params(skus: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T.nilable(T::Hash[Symbol, T.untyped])]) }
  def find_secret_and_code_skus(skus)
    secret_scanning_sku = skus.find { |sku| sku[:sku] == GitHub::Turboghas::SKU::SecretSecurity.to_param }
    code_security_sku   = skus.find { |sku| sku[:sku] == GitHub::Turboghas::SKU::CodeSecurity.to_param }
    [secret_scanning_sku, code_security_sku]
  end

  sig do
    params(
      business: Business,
      is_bundled_license: T::Boolean,
      is_metered_licensed: T::Boolean,
      is_unlimited_license: T::Boolean,
      skus: T::Array[T::Hash[Symbol, T.untyped]]
    ).returns(T.nilable(String))
  end
  def allowance_exceeded_banner_message(
    business:,
    is_bundled_license:,
    is_metered_licensed:,
    is_unlimited_license:,
    skus:
  )
    return if is_metered_licensed || is_unlimited_license || skus.empty?

    if is_bundled_license
      return format_exceeding_message(skus.first)
    end

    secret_scanning_sku, code_security_sku = find_secret_and_code_skus(skus)
    exceeding_secret = format_exceeding_message(secret_scanning_sku)
    exceeding_code   = format_exceeding_message(code_security_sku)

    if exceeding_secret && exceeding_code
      "You are using #{number_with_delimiter(T.must(secret_scanning_sku)[:consumedLicenses])} #{T.must(secret_scanning_sku)[:name]} " \
      "and #{number_with_delimiter(T.must(code_security_sku)[:consumedLicenses])} #{T.must(code_security_sku)[:name]} licenses, " \
      "exceeding their respective limits of #{number_with_delimiter(T.must(secret_scanning_sku)[:purchasedLicenses])} " \
      "and #{number_with_delimiter(T.must(code_security_sku)[:purchasedLicenses])}."
    else
      exceeding_secret || exceeding_code
    end
  end

  sig do
    params(
      business: Business,
      is_bundled_license: T::Boolean,
      is_metered_licensed: T::Boolean,
      is_unlimited_license: T::Boolean,
      skus: T::Array[T::Hash[Symbol, T.untyped]]
    ).returns(T.nilable(String))
  end
  def usage_at_capacity_banner_message(business:, is_bundled_license:, is_metered_licensed:, is_unlimited_license:, skus:)
    return if is_metered_licensed || is_unlimited_license || skus.empty?

    if is_bundled_license
      return format_at_capacity_message(skus.first)
    end

    secret_scanning_sku, code_security_sku = find_secret_and_code_skus(skus)
    at_capacity_secret = format_at_capacity_message(secret_scanning_sku)
    at_capacity_code   = format_at_capacity_message(code_security_sku)

    if at_capacity_secret && at_capacity_code
      "You are at capacity for your #{T.must(secret_scanning_sku)[:name]} and #{T.must(code_security_sku)[:name]} licenses."
    else
      at_capacity_secret || at_capacity_code
    end
  end
end
