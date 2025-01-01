# typed: true
# frozen_string_literal: true

require "monolith-twirp-webhooksubscriptions-subscriptions"

module Api::Internal::Twirp::Webhooksubscriptions
  module Subscriptions
    module V1
      # Handler for the MonolithTwirp::Webhooksubscriptions::Subscriptions::V1::SubscriptionsAPIService
      class SubscriptionsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[webhook_subscriptions]
        handles_service MonolithTwirp::Webhooksubscriptions::Subscriptions::V1::SubscriptionsAPIService

        # Public: Implementation of the WebhookSubscriptions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Webhooksubscriptions::Subscriptions::V1::WebhookSubscriptionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Webhooksubscriptions::Subscriptions::V1::WebhookSubscriptionsResponse, or a Twirp::Error.
        def webhook_subscriptions(req, env)
          return Twirp::Error.invalid_argument("missing event_type", argument: "token") if req.event_type.blank?
          return Twirp::Error.invalid_argument("missing event_guid", argument: "token") if req.event_guid.blank?

          hooks = T.let([], T::Array[Hook])
          installation_cache = T.let({}, T::Hash[Integer, IntegrationInstallation])

          err = catch(:halt) do
            if req.webhooks_delivery_scope&.hook_scope
              hooks = hook_scope_subscriptions(req.webhooks_delivery_scope.hook_scope)
            elsif req.webhooks_delivery_scope&.integration_scope
              hooks = integration_scope_subscriptions(req.webhooks_delivery_scope.integration_scope, req.event_type, req.repository_id)
            else
              hooks, installation_cache = default_subscriptions(req)
            end
          end
          return err if err.is_a?(Twirp::Error)

          subscriptions = hooks.filter_map do |hook|
            next unless hook.webhook?

            payload_version = Api::Versioning::default_version

            if Api::Versioning::usable_version?(hook.pinned_api_version)
              payload_version = hook.pinned_api_version
            end

            webhook = {
              id: hook.id,
              service: hook.name,
              needs_public_key_signature: Hook::DeliverySystem.needs_public_key_signature?(hook),
              configuration: hook.config_with_tenant_scoped_url,
              payload_version: payload_version
            }

            if hook.installation_target_type == Integration.to_s
              installation = installation_cache[hook.installation_target_id]
              unless installation.nil?
                webhook[:installation] = {
                  id: installation.id,
                  node_id: installation.global_relay_id,
                }
              end
            end

            {
              parent: hook.hookshot_parent_id,
              webhook: webhook
            }
          end

          {
            subscriptions: subscriptions
          }
        end

        private

        def subscribed_hooks_for_parent(parent, event_type, event_action)
          return [] unless parent
          if parent.is_a?(Repository)
            Hook.hooks_for_target(parent).active.to_a.select { |hook| hook.call?(event_type, action: event_action.to_sym) }
          else
            parent.hooks.active.to_a.select { |hook| hook.call?(event_type, action: event_action.to_sym) }
          end
        end

        def is_allowed_by_oauth_application_policy?(oauth_application, target_repository, target_organization)
          if target_repository.present?
            target_repository.public? || OauthApplicationPolicy::Application.new(target_repository, oauth_application).satisfied?
          else
            return false unless target_organization
            target_organization.allows_oauth_application?(oauth_application)
          end
        end

        def is_actions_delivery?(parent)
          Hook::ActionsDependency.is_actions_delivery?(parent)
        end

        def is_chatops_integration_delivery?(parent)
          parent == "integration-#{GitHub.slack_github_app&.id}" || parent == "integration-#{GitHub.msteams_github_app&.id}"
        end

        # Returns the hooks for the given hook scope and throws error if not found
        sig { params(hook_scope: T.untyped).returns(T::Array[Hook]) }
        def hook_scope_subscriptions(hook_scope)
          return [] if hook_scope.hook_id.blank?

          hook = Hook.find_by(id: hook_scope.hook_id.value)
          if hook.nil?
            throw :halt, Twirp::Error.not_found("Hook not found", entity: "hook", id: hook_scope.hook_id.value.to_s)
          end
          [hook]
        end

        sig { params(integration_scope: T.untyped, event_type: String, repository_id: T.untyped).returns(T::Array[Hook]) }
        def integration_scope_subscriptions(integration_scope, event_type, repository_id)
          return [] if integration_scope.integration_id.blank?

          integration = Integration.find_by(id: integration_scope.integration_id.value)
          if integration.nil?
            throw :halt, Twirp::Error.not_found("Integration not found", entity: "integration", id: integration_scope.integration_id.value.to_s)
          end

          return [] unless integration.active_and_subscribable?

          if repository_id
            subject = Repositories.domain.by_id(repository_id.value)

            # Get the resources that the integration needs to have access to see the event type
            resources = Repository::Resources.subject_types

            # check that the app is installed with permissions to the target repository
            installations = T.unsafe(integration.installations.not_suspended).with_resources_on(subject:, resources:)
            installation_ids = installations.pluck(:id)

            # If there are no installations with access to the target repository, return no subscriptions
            return [] if installation_ids.empty?

            # If the subscription check is required, check that the event is subscribed to by at least one of the installations
            unless integration_scope.skip_subscription_check
              subscribed = HookEventSubscription.with_name_and_subscriber(event_type, "IntegrationInstallation", installation_ids).any?
              return [] unless subscribed
            end
          end

          # The Integration#active_and_subscribable? check already ensures the hook is present
          [T.must(integration.hook)]
        end

        def default_subscriptions(req)
          target_repository = T.let(nil, T.nilable(Repository))
          target_organization = T.let(nil, T.nilable(Organization))
          target_business = T.let(nil, T.nilable(Business))
          target_marketplace_listing = T.let(nil, T.nilable(Marketplace::Listing))
          target_sponsors_listing = T.let(nil, T.nilable(SponsorsListing))
          integration_hooks = T.let([], T::Array[Hook])
          integrator_hooks = T.let([], T::Array[Hook])
          business_hooks = T.let([], T::Array[Hook])
          org_hooks  = T.let([], T::Array[Hook])
          repo_hooks = T.let([], T::Array[Hook])
          marketplace_listing_hooks = T.let([], T::Array[Hook])
          sponsors_listing_hooks = T.let([], T::Array[Hook])
          installation_cache = T.let({}, T::Hash[Integer, IntegrationInstallation])

          ActiveRecord::Base.connected_to(role: :reading) do
            # rubocop:todo GitHub/AvoidCast
            target_repository = T.cast(Repositories.domain.by_id(req.repository_id.value), T.nilable((Repository))) if req.repository_id
            # rubocop:enable GitHub/AvoidCast

            target_organization = Organization.find_by(id: req.organization_id.value) if req.organization_id
            target_business = Business.find_by(id: req.business_id.value) if req.business_id
            target_marketplace_listing = Marketplace::Listing.find_by(id: req.marketplace_listing_id.value) if req.marketplace_listing_id
            target_sponsors_listing = SponsorsListing.find_by(id: req.sponsors_listing_id.value) if req.sponsors_listing_id

            installations = Hook::Event.get_subscribed_integration_installations(
              event_type: req.event_type,
              target_repository: target_repository,
              target_organization: target_organization
            )
            installation_cache = installations.index_by(&:integration_id)
            integration_hooks = Hook::Event.get_active_hooks_by_installation_target(
              installation_target_type: Integration,
              installation_target_id: installations.map(&:integration_id),
            )

            integrator_hooks = Hook.subscribed_to_integrator_event(req.event_type).active

            repo_hooks = subscribed_hooks_for_parent(target_repository, req.event_type, req.event_action)
            business_hooks = subscribed_hooks_for_parent(target_business, req.event_type, req.event_action)
            org_hooks = subscribed_hooks_for_parent(target_organization, req.event_type, req.event_action)
            marketplace_listing_hooks = subscribed_hooks_for_parent(target_marketplace_listing, req.event_type, req.event_action)
            sponsors_listing_hooks = subscribed_hooks_for_parent(target_sponsors_listing, req.event_type, req.event_action)
          end
          hooks = integration_hooks | integrator_hooks | repo_hooks | business_hooks | org_hooks | marketplace_listing_hooks | sponsors_listing_hooks

          hooks.select! do |hook|
            next false if is_actions_delivery?(hook.hookshot_parent_id)
            next false if is_chatops_integration_delivery?(hook.hookshot_parent_id)
            next true unless hook.oauth_application
            is_allowed_by_oauth_application_policy?(hook.oauth_application, target_repository, target_organization)
          end
          [hooks, installation_cache]
        end
      end
    end
  end
end
