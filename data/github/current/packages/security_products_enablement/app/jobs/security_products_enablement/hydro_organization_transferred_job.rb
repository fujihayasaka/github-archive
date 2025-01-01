# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # Note on GHES, there is only one business so organization transfers aren't thing
  class HydroOrganizationTransferredJob < OrganizationHydroMessageJob

    queue_as :hydro_security_products_enablement_organization_transfer

    retry_on_dirty_exit

    sig { void }
    def perform
      OrganizationTransferredJob.perform_later(
        organization_id: message.dig(:organization, :id),
        actor:,
        destination_enterprise:
      )
    end

    private

    sig { returns(T.nilable(User)) }
    memoize def actor
      User.find_by(id: message.dig(:actor, :id))
    end

    sig { returns(T.nilable(Business)) }
    memoize def destination_enterprise
      Business.find_by(id: message.dig(:destination_enterprise, :id))
    end
  end
end
