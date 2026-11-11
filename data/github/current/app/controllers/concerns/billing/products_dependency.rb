# typed: strict
# frozen_string_literal: true

module Billing::ProductsDependency
  extend T::Helpers

  include BillingSettingsHelper

  abstract!

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def all_products
    products_response = billing_platform_client.get_all_products
    products = if products_response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      products_response[:products]
    end
    products
  end

  sig { params(this_entity: Billing::Types::Account).returns(T::Array[String]) }
  def excluded_products_for(this_entity)
    return exclude_non_copilot_products(this_entity) if this_entity.is_a?(Business) && this_entity.is_copilot_standalone?

    excluded = []
    case this_entity
    when Business
      excluded << "ghec" unless this_entity.metered_plan?
      excluded << "ghas" unless this_entity.advanced_security_metered_for_entity? || this_entity.has_active_advanced_security_trial? || this_entity.advanced_security_trial_enabled_for_entity?
    when Organization
      excluded << "ghec"
      excluded << "ghas" unless this_entity.advanced_security_metered_for_entity? || this_entity.advanced_security_trial_enabled_for_entity?
    when User
      excluded.concat(%w(ghec ghas))
    end

    # Exclude models when entity is billed via Azure
    excluded << "models" if this_entity.metered_via_azure?

    # Exclude copilot product for customers that don't have access to Copilot
    excluded << "copilot" if should_exclude_copilot_product?(this_entity)

    # Exclude sandbox product when feature flag is not enabled
    excluded << "sandbox" unless this_entity.feature_flag_enabled?(:billing_enable_sandbox_product, default: false)

    # Exclude code_quality product when feature flag is not enabled
    excluded << "code_quality" unless this_entity.feature_flag_enabled?(:code_quality_licensify, default: false)

    excluded
  end

  sig { params(this_entity: Billing::Types::Account).returns(T::Boolean) }
  def spark_enabled?(this_entity)
    if this_entity.is_a?(Business)
      Copilot::Business.new(this_entity).spark_enabled?
    elsif this_entity.is_a?(Organization)
      Copilot::Organization.new(this_entity).spark_enabled?
    else
      Copilot::User.new(this_entity).spark_enabled?
    end
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def should_exclude_copilot_product?(entity)
    if entity.user?
      copilot_user = Copilot::Public::User.for(T.cast(entity, User))
      !copilot_user.has_ci_access?
    elsif entity.is_a?(Organization)
      copilot_org = Copilot::Organization.new(entity)
      !copilot_org.has_assigned_seats?
    elsif entity.is_a?(Business)
      copilot_business = Copilot::Business.new(entity)
      copilot_business.copilot_seat_count <= 0
    else
      false
    end
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def bill_preview_enabled?(entity)
    flag = entity.user? ? :billing_copilot_cfi_bill_preview : :billing_copilot_bill_preview
    return false unless entity.feature_flag_enabled?(flag, default: false)

    !should_exclude_copilot_product?(entity)
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    false
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products(entity)
    all_products.reject { |product| excluded_products_for(entity).include?(product[:name]) }
  end

  sig { params(business: T.untyped).returns(T::Array[String]) }
  def exclude_non_copilot_products(business)
    excluded = %w[actions ghes ghec ghas packages codespaces spark coding_agent git_lfs sandbox code_quality]
    if business.billed_through_azure_subscription?
      excluded << "models"
    end
    excluded
  end

  sig { params(entity: T.untyped, enabled_product_names: T.nilable(T::Array[String])).returns(T::Array[String]) }
  def enabled_skus_for_products(entity, enabled_product_names = nil)
    pricing_response = billing_platform_client.get_all_pricing
    return [] if pricing_response.is_a?(::Billing::Platform::Api::Error) || pricing_response[:pricings].blank?

    current_time = Time.current.utc.to_i # Use Time.current for timezone consistency

    pricings = pricing_response[:pricings]

    if enabled_product_names
      pricings = pricings.select { |pricing| enabled_product_names.include?(pricing[:product]) }
    end

    pricings
      .reject { |pricing| should_exclude_sku_for_entity?(pricing[:sku], entity) }
      .reject { |pricing| pricing[:effectiveAt] && pricing[:effectiveAt] > current_time } # Filter out SKUs not yet effective, treat nil as effective
      .map { |pricing| pricing[:sku] }
  end

  private

  sig { params(sku: String, entity: T.untyped).returns(T::Boolean) }
  def should_exclude_sku_for_entity?(sku, entity)
    # Exclude copilot_for_business for basic business plans and users
    if sku == "copilot_for_business"
      return true if entity.is_a?(Business) && entity.seats_plan_type == "basic"
      return true if entity.is_a?(User) && !entity.is_a?(Organization)
    end

    # Exclude copilot_enterprise for basic business plans and users
    if sku == "copilot_enterprise"
      return true if entity.is_a?(Business) && entity.seats_plan_type == "basic"
      return true if entity.is_a?(User)
    end

    # Exclude copilot_standalone for non-basic business plans, organizations, and users
    if sku == "copilot_standalone"
      return true if entity.is_a?(Business) && entity.seats_plan_type != "basic"
      return true if entity.is_a?(Organization)
      return true if entity.is_a?(User)
    end

    # Handle advanced security SKUs based on bundling
    if %w[ghas_secret_protection_licenses ghas_code_security_licenses ghas_licenses].include?(sku)
      if entity.respond_to?(:advanced_security_products_bundled?)
        if entity.advanced_security_products_bundled?
          return true if sku == "ghas_secret_protection_licenses" || sku == "ghas_code_security_licenses"
        else
          return true if sku == "ghas_licenses"
        end
      end
    end

    if sku == "code_review_premium_request"
      return true unless entity.feature_flag_enabled?(:billing_enable_code_review_sku, default: false)
    end

    if %w[copilot_ai_unit coding_agent_ai_unit spark_ai_unit].include?(sku)
      tbb_enabled = if entity.is_a?(User) && entity.user?
        Copilot::User.new(entity).use_token_based_billing?
      else
        billing_tbb_enabled?(entity)
      end
      return true unless tbb_enabled
    end

    if %w[sandbox_linux sandbox_memory sandbox_snapshot].include?(sku)
      return true unless entity.feature_flag_enabled?(:billing_enable_sandbox_product, default: false)
    end

    false
  end
end
