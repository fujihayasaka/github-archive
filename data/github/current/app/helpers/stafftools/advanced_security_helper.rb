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
      if GitHub.flipper[:ghas_self_serve_orgs].enabled?(user)
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

    def enabled_ghas_repositories_count(business:, sku:)
      GitHub::Turboghas.check_error(T.let(GitHub::Turboghas.client.get_enabled_repositories({ entity_id: business.id, entity_type: :ENTITY_TYPE_BUSINESS, limit: -1, features: sku.features }), Twirp::ClientResp[::Turboghas::Proto::GetEnabledRepositoriesResponse])).count
    rescue ::GitHub::Turboghas::ResponseError
      "Data unavailable"
    end
  end
end
