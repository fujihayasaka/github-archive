# typed: true
# frozen_string_literal: true

module Stafftools
  module AdvancedSecurityHelper
    # If changing these constants, also remember to check:
    # - app/controllers/stafftools/users/advanced_security_controller.rb
    # - app/assets/modules/github/staff/advanced-security-state.ts
    GHAS_STATE_DISABLED = "disabled"
    GHAS_STATE_UNLIMITED = "unlimited"
    GHAS_STATE_SEATS = "seats"

    GHAS_STATE_SELECT_OPTIONS = {
      "Not enabled" => GHAS_STATE_DISABLED,
      "Enabled with unlimited seating" => GHAS_STATE_UNLIMITED,
      "Enabled with seat limit" => GHAS_STATE_SEATS,
    }.freeze

    GHAS_STATE_SELECT_OPTIONS_SELF_SERVE_ORGS = {
      "Not enabled" => GHAS_STATE_DISABLED,
      "Enabled with seat limit" => GHAS_STATE_SEATS,
    }.freeze

    def ghas_state_select_options(user)
      if FeatureFlag.vexi.enabled_or_raise?(:ghas_self_serve_orgs, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        GHAS_STATE_SELECT_OPTIONS_SELF_SERVE_ORGS
      else
        GHAS_STATE_SELECT_OPTIONS
      end
    end

    def ghas_state_selected_option(user)
      return GHAS_STATE_DISABLED if !user.advanced_security_purchased_for_entity?
      return GHAS_STATE_UNLIMITED if user.advanced_security_license.unlimited_seats?
      GHAS_STATE_SEATS
    end

    sig { params(entity: T.any(Business, ::User), sku: GitHub::Turboghas::SKU).returns(T.any(String, Integer)) }
    def enabled_ghas_repositories_with_usage_count(entity:, sku:)
      if FeatureFlag.vexi.enabled?(:use_licensify_for_repo_enablements_count, entity, default: false)
        enabled_ghas_repositories_with_usage_count_from_licensify(entity: entity, sku: sku)
      else
        enabled_ghas_repositories_with_usage_count_from_turboghas(entity: entity, sku: sku)
      end
    end

    # Returns human-readable display name for a trial type symbol
    sig { params(trial_type: T.nilable(Symbol)).returns(T.nilable(String)) }
    def trial_type_display_name(trial_type)
      case trial_type
      when :sales_led
        "Sales-Led"
      when :ghas_stand_alone
        "Self-Serve"
      when :digital_front_door
        "Digital Front Door"
      end
    end

    private

    sig { params(entity: T.any(Business, ::User), sku: GitHub::Turboghas::SKU).returns(T.any(String, Integer)) }
    def enabled_ghas_repositories_with_usage_count_from_turboghas(entity:, sku:)
      entity_type = GitHub::Turboghas.entity_type_for(entity)

      req = Turboghas::Proto::GetEnabledRepositoriesRequest.new(entity_id: entity.id, entity_type: entity_type, limit: -1, features: sku.features)
      GitHub::Turboghas.check_error(GitHub::Turboghas.client.get_enabled_repositories(req)).count
    rescue ::GitHub::Turboghas::ResponseError
      "Data unavailable"
    end

    sig { params(entity: T.any(Business, ::User), sku: GitHub::Turboghas::SKU).returns(T.any(String, Integer)) }
    def enabled_ghas_repositories_with_usage_count_from_licensify(entity:, sku:)
      customer_id = entity.customer&.id
      return "Data unavailable" if customer_id.nil?

      product = ::Licensing::Licensify::LicensifyProduct.from_turboghas_sku(sku)

      # Get active customer licenses and extract repo enablement IDs
      active_repo_ids = ::Licensing.get_active_license_repo_ids(customer_id, product: product)

      active_repo_ids.size
    rescue ::Licensing::Licensify::LicensifyRequestFailed
      "Data unavailable"
    end
  end
end
