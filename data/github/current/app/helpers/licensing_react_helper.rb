# typed: strict
# frozen_string_literal: true

module LicensingReactHelper
  extend T::Helpers
  include BillingSettingsHelper
  include LicensingHistoryPresenter
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::NumberHelper
  include UrlHelper
  include Scientist

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

  sig { params(organization: Organization, viewer: User, use_licensify: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def teams_ghas_overview_react_payload(organization:, viewer:, use_licensify: false)
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
      use_licensify:,
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

  sig { params(business: Business, viewer: User, preopen_seat_management: T.nilable(T::Boolean), use_licensify: T::Boolean).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghas_overview_react_payload(business:, viewer:, preopen_seat_management: false, use_licensify: false)
    is_bundled_license = business.ghas_sku_purchased_for_entity?
    is_metered_licensed = business.advanced_security_products_metered?
    billable_entity = business

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
      use_licensify:,
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
      usageExceededMessage: allowance_exceeded_banner_message(
        business:,
        is_bundled_license:,
        is_metered_licensed:,
        skus:
      ),
      usageAtCapacityMessage: usage_at_capacity_banner_message(
        business:,
        is_bundled_license:,
        is_metered_licensed:,
        skus:
      )
    }
  end

  sig { params(business: Business).returns(T::Hash[Symbol, T.untyped]) }
  def ghe_common_react_payload(business)
    roles = admin_roles(business)
    is_metered_licensed = business.metered_plan?
    error = false

    ghe_billable = if is_metered_licensed
      begin
        business.license_attributer.ghe_billable_cloud_user_count
      rescue ::Licensing::Licensify::LicensifyRequestFailed
        error = true
        0
      end
    else
      business.purchased_enterprise_licenses
    end

    begin
      ghe_consumed = if is_metered_licensed
        business.license_attributer.ghe_active_cloud_user_count
      else
        business.consumed_enterprise_licenses
      end
    rescue ::Licensing::Licensify::LicensifyRequestFailed
      error = true
      ghe_consumed = 0
    end

    # Use baseline seats logic for consistency with price calculations
    baseline_seats = business.purchased_enterprise_licenses(pending_cycle: true)
    manage_seats = Business::ManageSeats.new(business: business, new_seats: nil, baseline_seats: baseline_seats)
    current_payment = if is_metered_licensed && ghe_consumed == 0
      Billing::Money.new(0).format
    elsif is_metered_licensed
      Billing::Money.new(ghe_billable * GitHub::Plan.business_plus.unit_cost_in_cents).format
    else
      manage_seats.current_payment
    end

    # account for ended enterprise agreements that still have active BLAs
    # this is a temporary solution until we clean up the underlying data (ie. blas should be revoked and unattached)
    active_agreements_numbers = business.enterprise_agreements.active.pluck(:agreement_id)
    active_blas = business.bundled_license_assignments.where(enterprise_agreement_number: active_agreements_numbers)

    purchased_volume_licenses_with_overages = [business.purchased_volume_licenses, active_blas.count].max

    # Use uncached VSS counts
    vss_consumed = business.license_attributer.consumed_vss_licenses

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
      vssLicensesConsumed: vss_consumed,
      vssLicensesPurchasedWithOverage: purchased_volume_licenses_with_overages,
      canViewMembers: roles.include?("owner"),
      error:,
    }
  end

  sig { params(business: Business, current_user: T.nilable(User)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_details_react_payload(business:, current_user: nil)
    payload = ghe_common_react_payload(business)
    payload.merge(
      isHistoryEnabled: show_licensing_history?(business:, current_user:)
    )
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_details_summary_react_payload(business:)
    ghe_common_react_payload(business)
  end

  sig do
    params(
      business: Business,
      preopen_seat_management: T.nilable(T::Boolean),
      is_stafftools: T.nilable(T::Boolean),
      current_user: T.nilable(User)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def ghe_overview_react_payload(business:, preopen_seat_management: false, is_stafftools: false, current_user: nil)
    payload = ghe_common_react_payload(business)
    is_self_serve = business.eligible_for_self_serve_payment?
    is_self_serve_blocked = !is_self_serve || business.downgraded_to_free_plan? || business.dunning? || business.enterprise_managed?
    pending_cycle_change = is_self_serve_blocked ? nil : pending_cycle_seat_change_payload(business)

    can_manage_details = (payload[:canViewMembers] || is_stafftools) && (business.has_active_vss_bundle? || show_licensing_history?(business:, current_user:))

    payload.merge(
      canManageDetails: can_manage_details,
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
      vs_filter: String,
      is_stafftools: T::Boolean
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def ghe_licensee_list_page_payload(business:, search:, page:, per_page:, vs_filter: "all", is_stafftools: false)
    current_user = T.cast(T.unsafe(self).current_user, User)

    # Prepare what we need to distinguish license types for query filter
    vss_license_user_ids = Set.new(business.license_attributer.bundled_license_assignment_user_ids(skip_cache: true) || [])
    vss_manual_match_user_ids = business.license_attributer.bundled_license_assignment_manual_match_user_ids
    has_unassigned_user_blas_left = business.license_attributer.any_unassigned_user_bundled_license_assignments?
    all_license_user_ids = business.license_attributer.user_ids
    non_vss_license_user_ids = all_license_user_ids - vss_license_user_ids

    # Determine which user IDs to include based on vs_filter
    filtered_user_ids = case vs_filter
    when "manually-matched"
      vss_license_user_ids.select { |user_id| vss_manual_match_user_ids.include?(user_id) }
    when "automatically-matched"
      vss_license_user_ids.select { |user_id| !vss_manual_match_user_ids.include?(user_id) }
    when "unmatched"
      non_vss_license_user_ids
    when "all"
      all_license_user_ids
    end

    # Get business members based on the filtered user IDs
    members = business.filtered_members(
      current_user,
      ignore_org_membership_visibility: is_stafftools,
      query: search || "",
      deployment: "cloud", # exclude server-only users
      include_unaffiliated: false # exclude unaffiliated users
    )
      .where(user_id: filtered_user_ids) # only include users with licenses matching the filter
      .paginate(page:, per_page:) # apply pagination at the query level
      .includes(:user) # preload user association to avoid N+1 queries below

    # Prepare list of business owners once for access type determination
    # Use a set for efficient lookups
    owner_ids = business.owners.pluck(:id).to_set

    licensees = members.filter_map do |m|
      user = m.is_a?(BusinessUserAccount) ? m.user : m
      user_id = user&.id
      license_type = if vss_license_user_ids.include?(user_id)
        "Visual Studio"
      elsif non_vss_license_user_ids.include?(user_id)
        "Enterprise"
      else
        # Skip unlicensed users
        next
      end

      {
        member: m,
        user: user,
        user_id: user_id,
        license_type: license_type,
        is_manually_matched: license_type == "Visual Studio" ? vss_manual_match_user_ids.include?(user_id) : false,
        login: user&.display_login,
        name: user&.profile_name || user&.name,
        avatar_url: user&.primary_avatar_url,
        access_type: owner_ids.include?(user_id) ? "Admin" : "Member"
      }
    end

    bundled_license_assignment_map = ::Licensing::BundledLicenseAssignment
      .where(user_id: licensees.map { |info| info[:user_id] }.compact)
      .nonrevoked
      .pluck(:user_id, :id, :email, :identity)
      .to_h { |user_id, id, email, identity| [user_id, { id:, email:, identity: }] }

    {
      licensees: licensees.map do |info|
        {
          id: info[:user_id],
          accessType: info[:access_type],
          avatarUrl: info[:avatar_url],
          fullName: info[:name],
          isManuallyMatched: info[:is_manually_matched] || false,
          license: info[:license_type],
          login: info[:login],
          subscriptionIdentifier: bundled_license_assignment_map[info[:user_id]]
        }
      end,
      hasUnassignedVssSubscriptionsLeft: has_unassigned_user_blas_left,
      page: page,
      totalPages: (members.total_entries.to_f / per_page).ceil
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
    error = false


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

    # Use baseline seats logic for consistency with price calculations
    baseline_seats = business.purchased_enterprise_licenses(pending_cycle: true)
    manage_seats = Business::ManageSeats.new(business: business, new_seats: nil, baseline_seats: baseline_seats)
    has_enterprise_server = business.enterprise_installations.any?

    ghes_license_count = 0
    ghes_billable_license_count = 0
    has_metered_ghe = business.metered_plan?
    if has_metered_ghe
      begin
        ghes_license_count = business.license_attributer.ghe_active_server_only_user_count
        ghes_billable_license_count = business.license_attributer.ghe_billable_server_only_user_count
      rescue ::Licensing::Licensify::LicensifyRequestFailed
        error = true
        ghes_license_count = 0
        ghes_billable_license_count = 0
      end
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
      error:,
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
    ghec_trial_expired = business.trial_expired?
    trial_expiration_date = business.trial_expires_at&.strftime("%B %-d, %Y")
    is_trial = business.has_ongoing_copilot_business_trial? || business.digital_front_door?
    is_dfd_trial = business.trial? && business.dfd_trial?
    is_authenticated_through_dfd = business.authenticated_through_digital_front_door?
    {
      isCopilotEnabled: copilot_enabled,
      copilotCanBeReenabled: copilot_can_be_reenabled,
      businessSlug: business_slug,
      copilotTocLink: copilot_toc_link,
      cfbHelpLink: cfb_help_link,
      cfeHelpLink: cfe_help_link,
      isTrial: is_trial,
      ghecTrialExpired: ghec_trial_expired,
      trialExpirationDate: trial_expiration_date,
      isDfdTrial: is_dfd_trial,
      isAuthenticatedThroughDfd: is_authenticated_through_dfd
    }.merge(copilot_licensing_information(business))
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_details_react_payload(business:)
    copilot_business = Copilot::Business.new(business)
    enablement_setting = copilot_business.copilot_business_enablement_setting
    enabled_organization_count = copilot_business.copilot_enabled_organizations_count
    enabled_user_count = Copilot::Seat.business_owned(business).where(copilot_seat_assignments: { assignable_type: "User" }).count
    enabled_business_team_count = Copilot::SeatAssignment.business_team_assignments(business).count
    is_trial = business.trial?

    {
      enablementSetting: enablement_setting,
      enabledOrganizationCount: enabled_organization_count,
      enabledBusinessTeamCount: enabled_business_team_count,
      enabledUserCount: enabled_user_count,
      isTrial: is_trial,
    }
    .merge(copilot_licensing_information(business))
  end

  # Public: Checks if the business has the feature flags needed to support Copilot user assignment
  #
  # business - The Business to check feature flags on
  #
  # Returns true if the business has the feature flags enabled, false otherwise
  sig { params(business: Business).returns(T::Boolean) }
  def business_has_copilot_user_assignment_flags_enabled?(business:)
    return false if business.trial? && !business.feature_flag_enabled?(:copilot_user_assignment_for_trials, default: false)
    business.feature_flag_enabled?(:copilot_business_user_assignment, default: false)
  end

  # Public: Checks if the business has the feature flags needed to support Copilot Business Team assignment
  #
  # business - The Business to check feature flags on
  #
  # Returns true if the business has the feature flags enabled, false otherwise
  sig { params(business: Business).returns(T::Boolean) }
  def business_has_copilot_business_team_assignment_flags_enabled?(business:)
    return false unless BusinessTeam.enabled_for_enterprise?(business: business)
    return false if business.trial? && !business.feature_flag_enabled?(:copilot_user_assignment_for_trials, default: false)
    business.feature_flag_enabled?(:copilot_business_enterprise_team_assignment, default: false)
  end

  private

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
    billing_term_end_date = business.next_billing_date&.strftime("%B %-d, %Y")
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
      use_licensify: T::Boolean,
    ).returns(T::Hash[Symbol, Integer])
  end
  def calculate_billable_licenses(billable_entity:, is_bundled_license:, is_metered_licensed:, use_licensify:)
    case [is_metered_licensed, is_bundled_license]
    when [true, true]
      { bundled: billable_entity.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled, use_licensify:) }
    when [true, false]
      {
        secret_scanning: billable_entity.secret_protection_purchased? ? billable_entity.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::SecretSecurity, use_licensify:) : 0,
        code_security: billable_entity.code_security_purchased? ? billable_entity.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::CodeSecurity, use_licensify:) : 0
      }
    when [false, true]
      { bundled: billable_entity.advanced_security_license.seats }
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
      use_licensify: T::Boolean,
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def calculate_skus_with_pricing(billable_entity:, is_bundled_license:, is_metered_licensed:, use_licensify:)
    skus = []
    billable_licenses = calculate_billable_licenses(
      billable_entity:,
      is_bundled_license:,
      is_metered_licensed:,
      use_licensify:
    )

    if is_bundled_license
      license = billable_entity.advanced_security_license
      licensify_attributer = AdvancedSecurity::LicenseAttributer.new(billable_entity, product: Licensing::Licensify::LicensifyProduct::GHAS)

      unit_price = billable_entity.advanced_security_unit_price(sku: "ghas_licenses")
      billable_license_count = T.must(billable_licenses[:bundled])
      server_only_consumed_licenses = 0
      if billable_entity.is_a?(Business)
        server_only_counts = server_only_ghas_license_counts(business: billable_entity, sku: GitHub::Turboghas::SKU::Bundled)
        server_only_consumed_licenses = server_only_counts[:consumed_license_count] || 0
      end

      extra_seats = license.additional_metered_seats

      skus << {
        sku: GitHub::Turboghas::SKU::Bundled.to_param,
        name: "Advanced Security",
        consumedLicenses: use_licensify ? licensify_attributer.active_cloud_user_count : license.consumed_seats + extra_seats,
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
        license = billable_entity.secret_protection
        licensify_attributer = AdvancedSecurity::LicenseAttributer.new(billable_entity, product: Licensing::Licensify::LicensifyProduct::SECRET_PROTECTION)

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
          consumedLicenses: use_licensify ? licensify_attributer.active_cloud_user_count : license.seats_used,
          purchasedLicenses: license.seats,
          unitPrice: secret_scanning_unit_price.to_f,
          billableLicenses: secret_scanning_billable_licenses,
          billableAmount: billable_entity.advanced_security_price_for_sku(
            sku: "ghas_secret_protection_licenses",
            seats: secret_scanning_billable_licenses,
            unit_price: secret_scanning_unit_price
          ).to_f,
          serverOnlyConsumedLicenses: server_only_consumed_licenses,
          unlimitedLicense: license.unlimited_seats?,
        }
      end

      if billable_entity.code_security_purchased?
        license = billable_entity.code_security
        licensify_attributer = AdvancedSecurity::LicenseAttributer.new(billable_entity, product: Licensing::Licensify::LicensifyProduct::CODE_SECURITY)

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
          consumedLicenses: use_licensify ? licensify_attributer.active_cloud_user_count : license.seats_used,
          purchasedLicenses: license.seats,
          unitPrice: code_security_unit_price.to_f,
          billableLicenses: code_security_billable_licenses,
          billableAmount: billable_entity.advanced_security_price_for_sku(
            sku: "ghas_code_security_licenses",
            seats: code_security_billable_licenses,
            unit_price: code_security_unit_price
          ).to_f,
          serverOnlyConsumedLicenses: server_only_consumed_licenses,
          unlimitedLicense: license.unlimited_seats?,
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
    return if sku.nil? || sku[:unlimitedLicense]
    return unless sku[:consumedLicenses] == sku[:purchasedLicenses]

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
      skus: T::Array[T::Hash[Symbol, T.untyped]]
    ).returns(T.nilable(String))
  end
  def allowance_exceeded_banner_message(
    business:,
    is_bundled_license:,
    is_metered_licensed:,
    skus:
  )
    return if is_metered_licensed || skus.empty?

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
      skus: T::Array[T::Hash[Symbol, T.untyped]]
    ).returns(T.nilable(String))
  end
  def usage_at_capacity_banner_message(business:, is_bundled_license:, is_metered_licensed:, skus:)
    return if is_metered_licensed || skus.empty?

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
