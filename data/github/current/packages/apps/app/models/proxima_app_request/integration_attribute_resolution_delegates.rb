# typed: strict
# frozen_string_literal: true

class ProximaAppRequest
  module IntegrationAttributeResolutionDelegates
    # The DefaultDelegate implements what we expect to be the most common
    # behavior for synchronizable attributes.
    #
    # It respects the synchronization behavior that was determined in
    # https://github.com/github/ecosystem-apps/issues/3442
    #
    # It will sync static values and omit values that should be generated on
    # Proxima (e.g. secrets)
    #
    # It is expected that most integrations will not need to implement their own
    # delegate, and can instead use this one. However, if an Application needs to
    # specify special behavior for a particular attribute, it can do so by
    # implementing a custom delegate.
    class DefaultDelegate
      extend AttributeResolution::BaseDelegate
      extend AttributeResolution::Resolvers

      ATTRIBUTE_SYNC_POLICY = T.let(
        {
          integration: {
            id: :ineligible,
            bot_id: :ineligible,
            name: :sync,
            url: :sync,
            description: :sync,
            visibility: :sync,
            slug: :sync,
            key: :sync,
            setup_url: :sync,
            bgcolor: :sync,
            setup_on_update: :sync,
            deleted_at: :sync,
            request_oauth_on_install: :sync,
            user_token_expiration: :sync,
            state: :sync,
            suspended_at: :sync,
            user_suspended_by_id: :ineligible,
            pinned_api_version: :sync,
            device_flow_enabled: :sync,
            default_permissions: :sync,
            canonical_avatar_url: :sync,
          },
          latest_version: {
            id: :ineligible,
            note: :sync,
            default_permissions: :sync,
            default_events: :sync,
            single_file_name: :sync
          },
          application_callback_urls: {
            id: :ineligible,
            url: :sync,
            application_id: :ineligible,
            application_type: :ineligible,
            matching_strategy: :sync,
          },
          hook: {
            id: :ineligible,
            name: :sync,
            active: :sync,
            confirmed: :sync,
            installation_target_type: :ineligible,
            installation_target_id: :ineligible,
            oauth_application_id: :ineligible,
            pinned_api_version: :sync,
            url: :sync,
            secret: :sync,
            content_type: :sync,
            insecure_ssl: :sync
          },
          integration_install_triggers: {
            id: :ineligible,
            integration_id: :ineligible,
            install_type: :sync,
            path: :sync,
            reason: :sync,
            deactivated: :sync,
          },
          ip_allowlist_entries: {
            id: :ineligible,
            allow_list_value: :sync,
            range_from: :sync,
            range_to: :sync,
            name: :sync,
            active: :sync,
          },
          client_secrets: {
            id: :ineligible,
            oauth_application_id: :ineligible,
            creator_id: :ineligible,
            secret_hash: :sync,
            secret_last_eight: :sync,
            accessed_at: :ineligible,
            created_at: :ineligible,
            updated_at: :ineligible,
          },
          public_keys: {
            id: :ineligible,
            integration_id: :ineligible,
            creator_id: :ineligible,
            public_pem: :ineligible,
            created_at: :ineligible,
            updated_at: :ineligible,
          },
          owner: {
            dotcom_id: :sync,
            dotcom_type: :sync,
            dotcom_node_id: :sync,
            login: :sync,
            display_login: :sync,
            url: :sync,
            avatar_url: :sync,
          }
        }.freeze,
        T::Hash[Symbol, T::Hash[Symbol, Symbol]]
      )

      # This method is responsible for returning the value of an Integration's attribute  with respect
      # to ATTRIBUTE_SYNC_POLICY hash.
      # If the attribute corresponds to an association, the return value may be a hash or an array of hashes.
      sig { override.params(app: Integration, attribute: Symbol, stamp: T.nilable(String)).returns(T.untyped) }
      def self.synchronizable_attribute_value(app:, attribute:, stamp: nil)
        raise "Invalid attribute: #{attribute}" unless policy.key?(attribute) || T.must(policy[:integration]).key?(attribute)

        # Return the attribute value if it is explicitly marked as syncable
        case attribute
        when :latest_version
          resolve_latest_version(app: app)
        when :application_callback_urls
          resolve_application_callback_urls(app: app)
        when :hook
          resolve_hook(app: app)
        when :integration_install_triggers
          resolve_integration_install_triggers(app: app)
        when :ip_allowlist_entries
          resolve_ip_allowlist_entries(app: app)
        when :client_secrets
          resolve_client_secrets(app: app)
        when :state
          resolve_state(app: app)
        when :canonical_avatar_url
          resolve_canonical_avatar_url(app: app)
        when :owner
          resolve_owner(owner: app.owner)
        when :public_keys
          resolve_public_keys(app: app)
        else
          resolve_attribute(record: app, parent: :integration, attribute_name: attribute)
        end
      end

      sig { override.returns(T::Hash[Symbol, T::Hash[Symbol, Symbol]]) }
      def self.policy
        ATTRIBUTE_SYNC_POLICY
      end
    end

    # A delegate for 3rd party integrations.
    class ThirdPartyDelegate < DefaultDelegate
      ATTRIBUTE_SYNC_POLICY = T.let(
        {
          integration: {
            id: :ineligible,
            bot_id: :ineligible,
            name: :sync,
            url: :sync,
            description: :sync,
            visibility: :sync,
            slug: :sync,
            key: :sync,
            setup_url: :sync,
            bgcolor: :sync,
            setup_on_update: :sync,
            deleted_at: :sync,
            request_oauth_on_install: :sync,
            user_token_expiration: :sync,
            state: :sync,
            suspended_at: :sync,
            user_suspended_by_id: :ineligible,
            pinned_api_version: :sync,
            device_flow_enabled: :sync,
            default_permissions: :sync,
            canonical_avatar_url: :sync,
          },
          latest_version: {
            id: :ineligible,
            note: :sync,
            default_permissions: :sync,
            default_events: :sync,
            single_file_name: :sync
          },
          application_callback_urls: {
            id: :ineligible,
            url: :sync,
            application_id: :ineligible,
            application_type: :ineligible,
            matching_strategy: :sync,
          },
          hook: {
            id: :ineligible,
            name: :sync,
            active: :sync,
            confirmed: :sync,
            installation_target_type: :ineligible,
            installation_target_id: :ineligible,
            oauth_application_id: :ineligible,
            pinned_api_version: :sync,
            url: :sync,
            secret: :sync,
            content_type: :sync,
            insecure_ssl: :sync
          },
          integration_install_triggers: {
            id: :ineligible,
            integration_id: :ineligible,
            install_type: :sync,
            path: :sync,
            reason: :sync,
            deactivated: :sync,
          },
          ip_allowlist_entries: {
            id: :ineligible,
            allow_list_value: :sync,
            range_from: :sync,
            range_to: :sync,
            name: :sync,
            active: :sync,
          },
          client_secrets: {
            id: :ineligible,
            oauth_application_id: :ineligible,
            creator_id: :ineligible,
            secret_hash: :sync,
            secret_last_eight: :sync,
            accessed_at: :ineligible,
            created_at: :ineligible,
            updated_at: :ineligible,
          },
          public_keys: {
            id: :ineligible,
            integration_id: :ineligible,
            creator_id: :ineligible,
            public_pem: :sync,
            created_at: :ineligible,
            updated_at: :ineligible,
          },
          owner: {
            dotcom_id: :sync,
            dotcom_type: :sync,
            dotcom_node_id: :sync,
            login: :sync,
            display_login: :sync,
            url: :sync,
            avatar_url: :sync,
          }
        }.freeze,
        T::Hash[Symbol, T::Hash[Symbol, Symbol]]
      )

      sig { override.returns(T::Hash[Symbol, T::Hash[Symbol, Symbol]]) }
      def self.policy
        ATTRIBUTE_SYNC_POLICY
      end
    end

    # A delegate for the Dependabot integration that extends the default sync policy to
    # make a few webhook attributes ineligible for sync.  The values are unique per-stamp.
    class DependabotDelegate < DefaultDelegate
      ATTRIBUTE_SYNC_POLICY = T.let(
        {
          **DefaultDelegate::ATTRIBUTE_SYNC_POLICY,
          hook: {
            **DefaultDelegate::ATTRIBUTE_SYNC_POLICY.fetch(:hook, {}),
            secret: :ineligible,
            insecure_ssl: :ineligible
          },
        }.freeze,
        T::Hash[Symbol, T::Hash[Symbol, Symbol]]
      )

      sig { override.returns(T::Hash[Symbol, T::Hash[Symbol, Symbol]]) }
      def self.policy
        ATTRIBUTE_SYNC_POLICY
      end
    end
  end
end
