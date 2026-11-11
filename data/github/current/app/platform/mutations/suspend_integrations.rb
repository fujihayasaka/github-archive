# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SuspendIntegrations < Platform::Mutations::Base
      docs_category :apps
      description "Suspend or unsuspend integrations (to pps), individually or in bulk."

      SYNC_LIMIT = 20

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :integration_ids, [ID], "The global relay ids of integrations to act on.", required: false, loads: Objects::App, as: :integrations
      argument :action, Enums::IntegrationSuspensionAction, "Action to perform on integrations.", required: true
      argument :reason, String, "Reason for suspending integrations", required: false
      argument :owner_id, ID, "Owner to suspend/unsuspend all integrations for", required: false, loads: Unions::Account, as: :owner
      argument :async, Boolean, "Perform in a background job", required: false, default_value: false
      argument :dsa, Inputs::DsaRepositoryModerationAction, "The DSA repository moderation fields.", required: false
      argument :zendesk_ticket_url, String, "The Zendesk ticket URL associated with this moderation action", required: false
      argument :dsa_required, Boolean, "False if the violation was deemed inauthentic and should not publish a ModerationAction event", required: false, default_value: false

      field :success, Boolean, "Whether the operation completed successfully.", null: true
      error_fields

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(action:, integrations: nil, owner: nil, reason: nil, async: false, dsa: nil, dsa_required: true, zendesk_ticket_url: nil, **_inputs)
        zendesk_ticket_url ||= dsa&.zendesk_ticket_url
        zendesk_ticket_fields = DsaConstants.extract_zendesk_ticket_fields(zendesk_ticket_url)
        if zendesk_ticket_url.present? && zendesk_ticket_fields.nil?
          raise Errors::Validation.new("Zendesk ticket URL must be a valid Zendesk agent ticket URL for an allowed GitHub Zendesk subdomain")
        end

        affected = []
        case action
        when "suspend"
          raise Errors::Validation.new("No integrations provided") unless integrations&.any?
          raise Errors::Validation.new("Reason required to suspend") if reason.blank?

          if integrations.count > SYNC_LIMIT && !async
            raise Errors::Validation.new("Too many integrations for sync processing. Use async: true for #{integrations.count} integrations (limit: #{SYNC_LIMIT})")
          end

          if async
            SpamuraiSuspendIntegrationsJob.perform_later(
              integration_ids: integrations.map(&:id),
              action: "suspend",
              reason: reason,
              actor_id: context[:viewer].id,
              dsa_required: dsa_required,
              content_formats: dsa&.content_formats,
              source: dsa&.dsa_source,
              tos_reason: dsa&.tos_reason,
              zendesk_ticket_id: zendesk_ticket_fields&.dig(:zendesk_ticket_id),
              zendesk_subdomain: zendesk_ticket_fields&.dig(:zendesk_subdomain),
            )
          else
            integrations.each do |integration|
              success = integration.suspend(
                actor: context[:viewer],
                reason: reason
              )

              if success && dsa_required
                # Handle DSA instrumentation in the caller
                GlobalInstrumenter.instrument "staff.suspend_integration", {
                  actor: context[:viewer],
                  integration: integration,
                  reason: reason,
                  tos_reason: dsa&.tos_reason,
                  content_formats: dsa&.content_formats,
                  source: dsa&.dsa_source,
                  zendesk_ticket_id: zendesk_ticket_fields&.dig(:zendesk_ticket_id),
                  zendesk_subdomain: zendesk_ticket_fields&.dig(:zendesk_subdomain),
                }
              end

              affected << integration
            end
          end
        when "unsuspend"
          raise Errors::Validation.new("No integrations provided") unless integrations&.any?

          if integrations.count > SYNC_LIMIT && !async
            raise Errors::Validation.new("Too many integrations for sync processing. Use async: true for #{integrations.count} integrations (limit: #{SYNC_LIMIT})")
          end

          if async
            SpamuraiSuspendIntegrationsJob.perform_later(
              integration_ids: integrations.map(&:id),
              action: "unsuspend",
              actor_id: context[:viewer].id
            )
          else
            integrations.each do |integration|
              integration.unsuspend(actor: context[:viewer])
              affected << integration
            end
          end
        when "suspend_all_for_owner"
          raise Errors::Validation.new("No owner provided") unless owner
          raise Errors::Validation.new("Reason required to suspend all") if reason.blank?

          integrations_to_suspend = Integration.active.where(owner: owner).to_a
          suspended_count = integrations_to_suspend.count

          result = Integration.suspend_all_for_owner(
            actor: context[:viewer],
            owner: owner,
            reason: reason
          )

          # Handle DSA instrumentation in the caller
          if result && suspended_count > 0 && dsa_required
            GlobalInstrumenter.instrument "staff.suspend_integrations_bulk", {
              actor: context[:viewer],
              owner: owner,
              reason: reason,
              tos_reason: dsa&.tos_reason,
              content_formats: dsa&.content_formats,
              source: dsa&.dsa_source,
              zendesk_ticket_id: zendesk_ticket_fields&.dig(:zendesk_ticket_id),
              zendesk_subdomain: zendesk_ticket_fields&.dig(:zendesk_subdomain),
              integration_count: suspended_count
            }

            integrations_to_suspend.each do |integration|
              GlobalInstrumenter.instrument "staff.suspend_integration", {
                actor: context[:viewer],
                integration: integration,
                reason: reason,
                tos_reason: dsa&.tos_reason,
                content_formats: dsa&.content_formats,
                source: dsa&.dsa_source,
                zendesk_ticket_id: zendesk_ticket_fields&.dig(:zendesk_ticket_id),
                zendesk_subdomain: zendesk_ticket_fields&.dig(:zendesk_subdomain),
              }
            end
          end

          affected = Integration.suspended.where(owner: owner)
        when "unsuspend_all_for_owner"
          raise Errors::Validation.new("No owner provided") unless owner
          Integration.unsuspend_all_for_owner(actor: context[:viewer], owner: owner)
          affected = Integration.active.where(owner: owner)
        else
          raise Errors::Validation.new("Unknown action: #{action}")
        end

        { success: true, errors: [] }
      end
    end
  end
end
