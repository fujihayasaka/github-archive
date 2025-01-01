# typed: true
# frozen_string_literal: true

class Organization
  class LicenseHolder
    include Licensing::Licensify

    def initialize(organization)
      @organization = organization
    end

    # The Initial admins are created in an `after_commit` so we need to explicitly account for them here to pick them up
    # in the case we're dealing with an organization during its creation.
    def users
      @_users ||= begin
        LicenseSourcer.invites(organization, organization.pending_non_manager_invited_user_ids) +
        LicenseSourcer.collaborator_invites(organization, organization.private_repo_invitee_ids) +
        LicenseSourcer.members(organization, org_member_ids) +
        LicenseSourcer.collaborators(organization, organization.user_ids_with_private_repo_access) +
        LicenseSourcer.admins(organization, organization.admins.pluck(:id))
      end
    end

    def emails
      @_emails ||= begin
        LicenseSourcer.invites(organization, organization.pending_invited_non_user_emails) +
        LicenseSourcer.collaborator_invites(organization, organization.private_repo_non_user_invited_emails)
      end
    end

    private

    attr_reader :organization

    def org_member_ids
      e = GitHub::Licensing::Licensify::Experiment.new "organization_member_ids"
      e.context({
        organization_id: organization.id,
        customer_id: organization.customer&.id
      })

      e.use do
        organization.member_ids
      end

      e.try do
        licensify_req = Licensify::Services::V1::GetLicenseeIdsRequest.new(
          customerId: organization.customer&.id,
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          enablementReasons: [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP],
        )

        licensify_res = T.let(licensify_client.get_licensee_ids(licensify_req), Twirp::ClientResp[Licensify::Services::V1::GetLicenseeIdsResponse])
        if licensify_res.error.present?
          GitHub.logger.error(
            "Failed to get customer licenses for organization from Licensify: #{licensify_res.error}",
            {
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.organization.id": organization.id,
              "gh.customer.id": organization.customer&.id,
            },
          )
          next []
        end

        licensify_res.data.licenseeIds
      end

      e.compare_sorted_sequence

      # Only run the experiment if the organization is standalone and has a customer,
      # otherwise the experiment will just return the use block
      e.run_if { organization.licensed_customer_id && organization.licensed_customer_id == organization.customer&.id }
      e.run
    end
  end
end
