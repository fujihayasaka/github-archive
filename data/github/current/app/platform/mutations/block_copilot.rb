# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockCopilot < Platform::Mutations::Base
      description "Disable Copilot access via Copilot::AdminstrativeBlock"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_id, ID, "Global relay id of the user to add a staff note for.", required: true, loads: Objects::User
      argument :reason, String, "Reason for disabling the users", required: true
      argument :staff_note, String, "Adds a staff note to the repository owner", required: false
      argument :organization_id, ID, "The ID of the organization, pass if the whole org should be blocked", required: false, loads: Objects::Organization, as: :organization
      argument :superban, Boolean, "Indicates if payment method should be blocked", required: false, default_value: false

      field :id, String, "Global relay id of administrative block that was added.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(user:, **inputs)
        reason     = inputs[:reason]
        staff_note = inputs[:staff_note]
        organization = inputs[:organization]
        is_superban = !!inputs[:superban]

        GitHub.logger.with_named_tags("gh.user.id" => user.id, "gh.copilot.superban" => is_superban) do
          GitHub.logger.info("Processing block copilot for user")

          # Log if org passed is trusted
          if organization.present? && TrustTiers::Tier.for_billable_owner(organization).tier == TrustTiers::Tier::TRUSTED
            GitHub.logger.info("Attempting to block a Trusted organization: #{organization.id} is_superban: #{is_superban}")
          end

          # If it's a superban and organization was passed and is not Trusted,
          # block all members of the organization and block org payment method
          if is_superban && organization.present? && TrustTiers::Tier.for_billable_owner(organization).tier > TrustTiers::Tier::TRUSTED
            GitHub.logger.info("Processing block copilot superban for organization #{organization.id}")

            unless organization.members.include?(user)
              raise Errors::Unprocessable.new "User #{user.display_login} is not a member of the #{organization.display_login} organization."
            end

            organization.members.each do |member|
              next if member.id == user.id
              begin
                resolve(
                  user: member,
                  reason: reason.dup.prepend("Member of the same organization as user #{user.display_login} who was blocked with reason: "),
                  staff_note: staff_note,
                )
              rescue Errors::Unprocessable => e
                # do nothing if we fail to block any of the org members
              end
            end

            # Disable payment method if any, and trigger billing lock
            if !organization.payment_method.nil?
              Billing::Public.blocklist_payment_method(
                account: organization,
                payment_method: organization.payment_method,
                reason: reason.dup.prepend("Organization members are copilot admin blocked with reason: "),
                consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, # rubocop:disable Naming/InclusiveLanguage
                actor: context[:viewer],
              )
            end
          end

          copilot_user = ::Copilot::User.new(user)
          if copilot_user.administrative_blocked?
            raise Errors::Unprocessable.new "User is already administrative blocked from using Copilot."
          else
            if staff_note.present? && !GitHub.enterprise?
              StaffNote.create(
                user: context[:viewer],
                notable: user,
                note: staff_note,
              )
            end
            admin_block = copilot_user.administrative_block!(
              context[:viewer],
              reason,
              skip_hammy_check: false,
              send_block_email: false, # Hamzo calls this mutation and sends the email via SIRE
              superban: is_superban
            )
            { id: admin_block&.global_relay_id }
          end
        end
      end
    end
  end
end
