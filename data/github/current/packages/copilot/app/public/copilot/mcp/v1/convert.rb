# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      # Cross-major projection from the legacy `Copilot::Mcp::Registry` model
      # to the v1 wire shape. Modeled on `mcp-registry`'s
      # `internal/model/convert/v01.go` so the legacy model stays the source
      # of truth and the two routes are projections over the same data with
      # no drift — see RFC github/copilot-ecosystem#934 §2 and §1.
      #
      # Concretely the projection drops:
      #   * `registry_access`           (enforcement moves to the allowlist)
      #   * `owner.priority`            (order is the contract, not a number)
      module Convert
        sig { params(legacy: Copilot::Mcp::Registry).returns(Copilot::Mcp::V1::Registry) }
        def self.from_legacy(legacy)
          Copilot::Mcp::V1::Registry.new(
            url: legacy.url,
            owner: project_owner(legacy.owner),
            capabilities: legacy.capabilities,
          )
        end

        sig { params(owner: Copilot::Mcp::RegistryOwner).returns(Copilot::Mcp::V1::RegistryOwner) }
        def self.project_owner(owner)
          Copilot::Mcp::V1::RegistryOwner.new(
            # login is an attribute of the owner struct, not User#login
            # rubocop:disable GitHub/DoNotAllowLogin
            login: owner.login,
            # rubocop:enable GitHub/DoNotAllowLogin
            id: owner.id,
            type: owner.type,
            name: owner.name,
            parent_login: owner.parent_login,
            parent_id: owner.parent_id,
            parent_name: owner.parent_name,
          )
        end
      end
    end
  end
end
