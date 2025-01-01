# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::CollaboratorDependency
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
        business.outside_collaborator_ids(
          on_repositories_with_visibility: [:private],
          include_forks: false
        )
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

  # Note: This is expected to be used for Business::LicenseCsvUsageBuilder only.
  # Querying with GetCustomerLicensesRequest instead of GetLicenseeIdsRequest is a perf hit
  # and the outsideness checks here don't help!
  sig { returns(T::Array[Integer]) }
  memoize def business_private_outside_repo_collaborator_ids_licensify
    customer_licenses = business_private_repo_collaborator_ids_licensify

    # Any customer_license with enablement reason `ENABLEMENT_REASON_REPOSITORY_COLLABORATOR` is a private repo collaborator.
    # Collect all those enablement ids and then get the repo ids for each one.
    collaborator_repo_ids = customer_licenses.flat_map do |license|
      license.enablements
        .select { |e| e.reason == :ENABLEMENT_REASON_REPOSITORY_COLLABORATOR }
        .flat_map(&:enablementIds)
    end.uniq

    # Fetch the org ids for each repo and build a repo_id => org_id map to refer to
    repo_org_ids = Repository.where(id: collaborator_repo_ids).pluck(:id, :organization_id).to_h

    # Get _outside_ collaborator ids, where the licensee has a ENABLEMENT_REASON_REPOSITORY_COLLABORATOR enablement for a repo
    # But does not have a ENABLEMENT_REASON_ORG_MEMBERSHIP enablement for the org that that repo belongs to
    outside_collaborator_ids = customer_licenses.select do |license|
      # Collect org IDs from ORG_MEMBERSHIP enablements
      org_membership_org_ids = license.enablements
                                      .select { |e| e.reason == :ENABLEMENT_REASON_ORG_MEMBERSHIP }
                                      .flat_map(&:enablementIds)
                                      .uniq

      # Find repositories where the licensee is a collaborator but not a member of the org
      license.enablements.any? do |enablement|
        next false unless enablement.reason == :ENABLEMENT_REASON_REPOSITORY_COLLABORATOR

        enablement.enablementIds.any? do |repo_id|
          org_id = repo_org_ids[repo_id]
          next false unless org_id

          !org_membership_org_ids.include?(org_id)
        end
      end
    end.map { |license| T.must(license.licensee).id.to_i }.uniq
  end

  private

  # Note: This is expected to be used for business_private_outside_repo_collaborator_ids_licensify only, for CSV generation.
  # Querying with GetCustomerLicensesRequest instead of GetLicenseeIdsRequest is a step down in performance.
  sig { returns(T::Array[Licensify::Services::V1::CustomerLicense]) }
  def business_private_repo_collaborator_ids_licensify
    licensify_req = Licensify::Services::V1::GetCustomerLicensesRequest.new(
      customerId: business.customer_id,
      product: Licensify::Services::V1::Product::PRODUCT_SDLC,
    )
    licensify_res = licensify_client.get_customer_licenses(licensify_req)
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
      return []
    end

    licensify_res.data["customerLicenses"].to_a
  end
end
