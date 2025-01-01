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
        licensify_req = Licensify::Services::V1::GetLicenseeIdsByTypeRequest.new(
          customerId: organization.customer&.id,
          product: Licensify::Services::V1::Product::PRODUCT_SDLC,
          enablementReasons: [Licensify::Services::V1::EnablementReason::ENABLEMENT_REASON_ORG_MEMBERSHIP],
        )

        licensify_res = T.let(licensify_client.get_licensee_ids_by_type(licensify_req), Twirp::ClientResp[Licensify::Services::V1::GetLicenseeIdsByTypeResponse])
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

        user_ids = T.let([], T::Array[Integer])

        licensify_licensee_ids_by_type = licensify_res.data.licenseeIdsByType
        licensify_licensee_ids_by_type.each do |group|
          group = T.let(group, Licensify::Services::V1::LicenseeIdsByType)

          type = case group.type
          when Symbol
            Licensify::Services::V1::LicenseeType.resolve(T.cast(group.type, Symbol))
          else
            T.cast(group.type, Integer)
          end

          user_ids = user_ids.concat(group.licenseeIds.map(&:to_i)) if type == Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER
        end

        user_ids
      end

      e.compare_sorted_sequence

      # Only run the experiment if the organization is standalone and has a customer,
      # otherwise the experiment will just return the use block
      e.run_if { organization.licensed_customer_id && organization.licensed_customer_id == organization.customer&.id }
      e.run
    end
  end
end
