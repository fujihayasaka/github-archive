# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Mobile
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :mobile_updates_url, Scalars::URI, "A WebSocket URL for connecting to receive updates.",
    null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events]

    def mobile_updates_url
      GitHub::WebSocket.websocket_url(nil, @context[:viewer].id)
    end

    field :mobile_capabilities, resolver: Resolvers::MobileCapabilities, required_capabilities: [:mobile_only_schema_mask], description: "Returns all capabilities for the mobile clients"

    field :mobile_copilot_paywall, Objects::MobileCopilotPaywall, "Returns paywall configuration for Copilot on mobile", null: true, required_capabilities: [:mobile_only_schema_mask]

    def mobile_copilot_paywall
      viewer = @context[:viewer]
      if viewer && FeatureFlag.vexi.enabled?(:mobile_copilot_paywall_preview, viewer, default: false)
        # The preview data includes the Max SKU product, which uses the COPILOT_INDIVIDUAL_MAX
        # enum value gated behind copilot_iap_max_sku.

        unless FeatureFlag.vexi.enabled?(:copilot_iap_max_sku, viewer, default: false)
          Kernel.raise Platform::Errors::Validation, "The mobile_copilot_paywall_preview feature flag requires the copilot_iap_max_sku feature flag to also be enabled."
        end

        # We must add the flag to context[:feature_flags]
        # so the schema runtime mask allows the enum value through, since mobile clients don't send
        # the GraphQL-Features header. Remove this once the Max SKU is fully rolled out.
        @context[:feature_flags] << :copilot_iap_max_sku unless @context[:feature_flags].include?(:copilot_iap_max_sku)
        Mobile::Copilot::Paywall::Data.preview
      else
        paywall_data = Mobile::Copilot::Paywall::Data.default
        if viewer && FeatureFlag.vexi.enabled?(:copilot_iap_max_rollout, viewer, default: false)
          unless FeatureFlag.vexi.enabled?(:copilot_iap_max_sku, viewer, default: false)
            Kernel.raise Platform::Errors::Validation, "The copilot_iap_max_rollout feature flag requires the copilot_iap_max_sku feature flag to also be enabled."
          end

          @context[:feature_flags] << :copilot_iap_max_sku unless @context[:feature_flags].include?(:copilot_iap_max_sku)
          paywall_data
        else
          Mobile::Copilot::Paywall::Data.without_max(paywall_data)
        end
      end
    end

    field :viewer_updates_channel, String, "Channel value for subscribing to live updates.", null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events] do
      argument :name, Enums::UserPubSubTopic, "The name of the channel to use.", required: true
    end

    def viewer_updates_channel(**arguments)
      return nil unless @context[:viewer]

      case arguments[:name]
      when "notifications_changed"
        GitHub::WebSocket::Channels.signed_notifications_changed(@context[:viewer])
      when "marked_read"
        GitHub::WebSocket::Channels.signed_marked_as_read(@context[:viewer])
      end
    end
  end
end
