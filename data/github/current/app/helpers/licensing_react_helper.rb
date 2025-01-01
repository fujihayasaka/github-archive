# typed: strict
# frozen_string_literal: true

module LicensingReactHelper
  extend T::Helpers
  include BillingSettingsHelper
  include ActionView::Helpers::TextHelper

  FALLBACK_GHE_UNIT_PRICE = 21.0

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def payment_method_react_payload(business)
    return unless business.payment_method

    payment_method = business.payment_method
    {
      credit_card: payment_method.credit_card?,
      paypal: payment_method.paypal?,
      last_four: payment_method.last_four,
      card_type: payment_method.card_type,
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def trial_react_payload(business)
    return nil unless business.trial?

    {
      expirationDate: business.trial_expires_at.in_time_zone(GitHub::Billing.timezone).as_json,
      isActive: !business.trial_expired?,
      trialLicensesAllowed: business.purchased_enterprise_licenses,
    }
  end

  sig { params(business: Business, product: Symbol).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def invoice_license_react_payload(business:, product:)
    return nil unless business.feature_enabled?(:ghe_sales_serve_renewals)
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

  sig { params(business: Business, preopen_seat_management: T.nilable(T::Boolean)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghas_overview_react_payload(business:, preopen_seat_management: false)
    license = business.advanced_security_license
    is_bundled_license = business.advanced_security_products_bundled?
    is_metered_licensed = business.advanced_security_products_metered?

    billing_cycle = determine_billing_cycle(
      business:,
      is_bundled_license:,
      is_metered_licensed:
    )

    skus = calculate_skus_with_pricing(
      business:,
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

    {
      billingCycle: "#{billing_cycle.serialize.titleize}ly",
      billableLicenses: billable_licenses_val,
      billingTermEndDate: business.billing_term_ends_on&.in_time_zone(GitHub::Billing.timezone).as_json,
      currentPayment: Billing::Money.new(total_payment * 100).format,
      invoiceLicenseInfo: invoice_license_react_payload(business: business, product: :ghas),
      isAdvancedSecurityEnabled: business.advanced_security_purchased?,
      isBundled: is_bundled_license,
      isManagingSeats: preopen_seat_management && business.has_self_serve_advanced_security?,
      isMeteredLicensed: is_metered_licensed,
      isSelfServeAdvancedSecurity: business.has_self_serve_advanced_security?,
      paymentMethod: payment_method_react_payload(business),
      selfServeSubscriptionInfo: self_serve_ghas_subscription_payload(business),
      skus:,
      unlimitedLicense: license.unlimited_seats?,
    }
  end

  sig { params(business: Business, preopen_seat_management: T.nilable(T::Boolean)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_overview_react_payload(business:, preopen_seat_management: false)
    manage_seats = Business::ManageSeats.new(business: business, new_seats: nil)
    is_self_serve = business.eligible_for_self_serve_payment?
    is_self_serve_blocked = !is_self_serve || business.downgraded_to_free_plan? || business.dunning?
    pending_cycle_change = is_self_serve_blocked ? nil : pending_cycle_seat_change_payload(business)
    roles = admin_roles(business)

    consumed_licenses = if business.licensing_platform == Business::LicenseDependency::LicensingPlatform::Licensify
      business.license_attributer.license_counts[:ghe_active_cloud_user_count]
    else
      business.consumed_enterprise_licenses
    end

    is_metered_licensed = business.metered_plan?
    current_payment = if is_metered_licensed && consumed_licenses == 0
      Billing::Money.new(0).format
    elsif is_metered_licensed && business.licensing_platform == Business::LicenseDependency::LicensingPlatform::Licensify
      counts = business.license_attributer.license_counts
      ghe_billable_license_count = counts[:ghe_active_cloud_user_count] + counts[:ghe_deactivated_cloud_user_count] + counts[:ghe_suspended_cloud_user_count]
      Business::ManageSeats.new(business: business, new_seats: ghe_billable_license_count).new_payment
    else
      manage_seats.current_payment
    end

    {
      billingTermEndDate: business.billing_term_ends_on&.in_time_zone(GitHub::Billing.timezone).as_json,
      canViewMembers: roles.include?("owner"),
      currentPayment: current_payment,
      enterpriseLicensesConsumed: consumed_licenses,
      enterpriseLicensesPurchased: business.purchased_enterprise_licenses,
      invoiceLicenseInfo: invoice_license_react_payload(business: business, product: :ghec),
      isManagingSeats: preopen_seat_management && !business.metered_plan? && is_self_serve && !is_self_serve_blocked,
      isMonthly: business.plan_duration == User::BillingDependency::MONTHLY_PLAN,
      isSelfServe: is_self_serve,
      isSelfServeBlocked: is_self_serve_blocked,
      isVolumeLicensed: !is_metered_licensed,
      isVssEnabled: business.volume_licensing_enabled?,
      paymentMethod: payment_method_react_payload(business),
      pendingCycleChange: pending_cycle_change,
      trialInfo: trial_react_payload(business),
      unitCost: manage_seats.seat_cost_label_short,
      vssLicensesConsumed: business.consumed_volume_licenses,
      vssLicensesPurchasedWithOverage: business.purchased_volume_licenses_with_overages,
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
    due_date = business.billing_term_ends_on&.in_time_zone(GitHub::Billing.timezone).as_json
    has_enterprise_server = business.enterprise_installations.any?
    counts = business.license_attributer.license_counts
    ghes_license_count = counts[:ghe_active_server_only_user_count]
    ghes_billable_license_count = counts[:ghe_active_server_only_user_count] + counts[:ghe_deactivated_server_only_user_count] + counts[:ghe_suspended_server_only_user_count]

    ghes_unit_price = manage_seats.seat_change&.unit_price&.to_f || FALLBACK_GHE_UNIT_PRICE
    bundled_ghas_unit_price = business.advanced_security_price_for_sku(sku: "ghas_licenses", seats: 1).to_f
    code_security_unit_price = business.advanced_security_price_for_sku(sku: "ghas_code_security_licenses", seats: 1).to_f
    secret_protection_unit_price = business.advanced_security_price_for_sku(sku: "ghas_secret_protection_licenses", seats: 1).to_f

    {
      dueDate: due_date,
      hasEnterpriseServer: has_enterprise_server,
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
    business_slug = business.slug
    {
      isCopilotEnabled: copilot_enabled,
      businessSlug: business_slug,
      copilotTocLink: copilot_toc_link,
      cfbHelpLink: cfb_help_link,
      cfeHelpLink: cfe_help_link,
    }.merge(copilot_licensing_information(business))
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_details_react_payload(business:)
    copilot_licensing_information(business)
  end

  private

  sig { params(business: Business, sku: GitHub::Turboghas::SKU).returns(T::Hash[Symbol, Integer]) }
  def server_only_ghas_license_counts(business:, sku:)
    ghes_committers = business.advanced_security_license_for_sku(sku:).ghes_committers
    unmatched = Set.new(ghes_committers&.unmatched || [])
    consumed_license_count = unmatched.size

    previous_unmatched = MeteredAdvancedSecurityScheduledEmitterJob::BusinessEmitterJob.unmatched_ids(sku: sku, business: business)
    if previous_unmatched
      unmatched.merge(previous_unmatched)
    end

    billable_license_count = unmatched.size
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
      business: Business,
      is_bundled_license: T::Boolean,
      is_metered_licensed: T::Boolean,
      license: ::AdvancedSecurityLicense,
    ).returns(T::Hash[Symbol, Integer])
  end
  def calculate_billable_licenses(business:, is_bundled_license:, is_metered_licensed:, license:)
    case [is_metered_licensed, is_bundled_license]
    when [true, true]
      { bundled: business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::Bundled) }
    when [true, false]
      {
        secret_scanning: business.secret_protection_purchased? ? business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::SecretSecurity) : 0,
        code_security: business.code_security_purchased? ? business.advanced_security_billable_licenses(sku: GitHub::Turboghas::SKU::CodeSecurity) : 0
      }
    when [false, true]
      { bundled: license.seats }
    when [false, false]
      {
        secret_scanning: business.secret_protection_purchased? ? business.secret_scanning_license_count : 0,
        code_security: business.code_security_purchased? ? business.code_security_license_count : 0
      }
    else
      { bundled: 0 }
    end
  end

  sig { params(business: Business, is_metered_licensed: T::Boolean, is_bundled_license: T::Boolean).returns(Billing::Public::SubscriptionItems::BillingCycle) }
  def determine_billing_cycle(business:, is_metered_licensed:, is_bundled_license:)
    if is_metered_licensed
      return Billing::Public::SubscriptionItems::BillingCycle::Month
    end

    # For volume bundled licenses, there is no support for an annual billing cycle
    if is_bundled_license && business.plan_duration == User::BillingDependency::YEARLY_PLAN
      Billing::Public::SubscriptionItems::BillingCycle::Month
    else
      # Use the default billing cycle for the business
      Billing::Public::SubscriptionItems::BillingCycle.from_serialized(business.plan_duration)
    end
  end

  sig do
    params(
      business: Business,
      is_bundled_license: T::Boolean,
      is_metered_licensed: T::Boolean,
      license: ::AdvancedSecurityLicense,
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def calculate_skus_with_pricing(business:, is_bundled_license:, is_metered_licensed:, license:)
    skus = []
    billable_licenses = calculate_billable_licenses(
      business:,
      is_bundled_license:,
      is_metered_licensed:,
      license:
    )

    if is_bundled_license
      unit_price = business.advanced_security_unit_price(sku: "ghas_licenses")
      billable_license_count = T.must(billable_licenses[:bundled])

      skus << {
        sku: GitHub::Turboghas::SKU::Bundled.to_param,
        name: "Secret Protection and Code Security licenses",
        consumedLicenses: license.consumed_seats,
        purchasedLicenses: license.seats,
        unitPrice: unit_price.to_f,
        billableLicenses: billable_license_count,
        billableAmount: business.advanced_security_price_for_sku(
          sku: "ghas_licenses",
          seats: billable_license_count,
          unit_price: unit_price
        ).to_f
      }
    else
      if business.secret_protection_purchased?
        secret_scanning_unit_price = business.advanced_security_unit_price(sku: "ghas_secret_protection_licenses")
        secret_scanning_billable_licenses = T.must(billable_licenses[:secret_scanning])

        skus << {
          sku: GitHub::Turboghas::SKU::SecretSecurity.to_param,
          name: "Secret Protection",
          consumedLicenses: business.secret_protection.seats_used,
          purchasedLicenses: business.secret_protection.seats,
          unitPrice: secret_scanning_unit_price.to_f,
          billableLicenses: secret_scanning_billable_licenses,
          billableAmount: business.advanced_security_price_for_sku(
            sku: "ghas_secret_protection_licenses",
            seats: secret_scanning_billable_licenses,
            unit_price: secret_scanning_unit_price
          ).to_f
        }
      end

      if business.code_security_purchased?
        code_security_unit_price = business.advanced_security_unit_price(sku: "ghas_code_security_licenses")
        code_security_billable_licenses = T.must(billable_licenses[:code_security])

        skus << {
          sku: GitHub::Turboghas::SKU::CodeSecurity.to_param,
          name: "Code Security",
          consumedLicenses: business.code_security.seats_used,
          purchasedLicenses: business.code_security.seats,
          unitPrice: code_security_unit_price.to_f,
          billableLicenses: code_security_billable_licenses,
          billableAmount: business.advanced_security_price_for_sku(
            sku: "ghas_code_security_licenses",
            seats: code_security_billable_licenses,
            unit_price: code_security_unit_price
          ).to_f
        }
      end
    end

    skus
  end
end
