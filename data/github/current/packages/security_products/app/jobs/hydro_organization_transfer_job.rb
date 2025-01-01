# typed: strict
# frozen_string_literal: true

class HydroOrganizationTransferJob < OrganizationHydroMessageJob
  extend T::Sig
  queue_as :hydro_security_products_organization_transfer

  retry_on_dirty_exit

  sig { void }
  def perform
    OrganizationTransferJob.perform_later(organization_id: organization_id, original_message: message)
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def failbot_log_context
    super.merge({
      app: "github-security-center"
    })
  end
end
