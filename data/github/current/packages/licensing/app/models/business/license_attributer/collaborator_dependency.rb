# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::CollaboratorDependency
  extend T::Sig
  extend T::Helpers

  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { Business::LicenseAttributer }

  # Outside collaborators on private repositories, excluding forks.
  # These users consume a license.
  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def private_outside_collaborator_ids(skip_cache: false)
    return @private_outside_collaborator_ids if defined?(@private_outside_collaborator_ids)

    @private_outside_collaborator_ids = T.let(
      business.license_attributer_cache.ids("private_outside_collaborator_ids", skip_cache: skip_cache) do
        e = GitHub::Licensing::Licensify::Experiment.new "business_private_outside_collaborator_ids"
        e.context({
          business_id: business.id,
          customer_id: business.customer_id,
        })

        e.use do
          business.outside_collaborator_ids(
            on_repositories_with_visibility: [:private],
            include_forks: false
          )
        end

        e.try do
          licensify_req = Licensify::Services::V1::GetLicenseeIdsRequest.new(
            customerId: business.customer_id,
            product: Licensify::Services::V1::Product::PRODUCT_SDLC,
            enablementReasons: [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_REPOSITORY_COLLABORATOR],
          )
          licensify_res = licensify_client.get_licensee_ids(licensify_req)
          if licensify_res.error.present?
            GitHub.logger.error(
              "Failed to get customer licenses for business from Licensify: #{licensify_res.error}",
              {
                "code.namespace": self.class.name,
                "code.function": __method__,
                "gh.business.id": business.id,
                "gh.customer.id": business.customer_id,
              },
            )
            break []
          end

          # Exclude licensees who are members of the business's other organizations
          licensify_res.data["licenseeIds"] - business.organization_member_ids
        end

        # The license attributer may be called when a business signs up for a trial but before the business is saved, so
        # there is no customer yet. This will generate a mismatch since licensify has no records yet, so ignore the mismatch.
        e.ignore { !business.persisted? }
        e.compare_sorted_sequence
        e.run
      end,
      T.nilable(T::Array[Integer])
    )
  end

  # Outside collaborators that do not consume a license.
  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def nonlicensed_outside_collaborator_ids(skip_cache: false)
    return @nonlicensed_outside_collaborator_ids if defined?(@nonlicensed_outside_collaborator_ids)

    @nonlicensed_outside_collaborator_ids = T.let(
      business.license_attributer_cache.ids("nonlicensed_outside_collaborator_ids", skip_cache: skip_cache) do
        business.outside_collaborator_ids(
          on_repositories_with_visibility: [:public],
          include_forks: true
        )
      end,
      T.nilable(T::Array[Integer])
    )
  end

  sig { returns(T::Array[Integer]) }
  memoize def business_guest_collaborator_ids
    business.guest_collaborator_ids
  end
end
