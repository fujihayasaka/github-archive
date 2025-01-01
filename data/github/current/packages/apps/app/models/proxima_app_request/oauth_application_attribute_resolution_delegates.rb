# typed: true
# frozen_string_literal: true

class ProximaAppRequest
  module OauthApplicationAttributeResolutionDelegates

    # The DefaultDelegate implements what we expect to be the most common
    # behavior for synchronizable attributes.
    #
    # It respects the synchronization behavior that was determined in
    # https://github.com/github/ecosystem-apps/issues/3442
    #
    # It will sync static values and omit values that should be generated on
    # Proxima (e.g. secrets)
    #
    # It is expected that most OAuth Applications will not need to implement their own
    # delegate, and can instead use this one. However, if an Application needs to
    # specify special behavior for a particular attribute, it can do so by
    # implementing a custom delegate.
    class DefaultDelegate
      extend AttributeResolution::BaseDelegate
      extend AttributeResolution::Resolvers

      ATTRIBUTE_SYNC_POLICY = {
        oauth_application: {
          id: :ineligible,
          name: :sync,
          url: :sync,
          key: :sync,
          user_id: :ineligible,
          device_flow_enabled: :sync,
          canonical_avatar_url: :sync,
        },
        application_callback_urls: {
          id: :ineligible,
          url: :sync,
          application_id: :ineligible,
          application_type: :ineligible
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
        owner: {
          dotcom_id: :sync,
          dotcom_type: :sync,
          dotcom_node_id: :sync,
          login: :sync,
          display_login: :sync,
          url: :sync,
          avatar_url: :sync,
        }
      }

      sig { override.params(app: OauthApplication, attribute: Symbol, stamp: T.nilable(String)).returns(T.untyped) }
      def self.synchronizable_attribute_value(app:, attribute:, stamp: nil)
        raise "Invalid attribute: #{attribute}" unless ATTRIBUTE_SYNC_POLICY.key?(attribute) || T.must(ATTRIBUTE_SYNC_POLICY[:oauth_application]).key?(attribute)

        # Return the attribute value if it is explicitly marked as syncable
        case attribute
        when :application_callback_urls
          resolve_application_callback_urls(app: app)
        when :client_secrets
          resolve_client_secrets(app: app)
        when :owner
          resolve_owner(owner: app.owner)
        when :canonical_avatar_url
          resolve_canonical_avatar_url(app: app)
        else
          resolve_attribute(record: app, parent: :oauth_application, attribute_name: attribute)
        end
      end

      sig { override.returns(T::Hash[Symbol, T::Hash[Symbol, Symbol]]) }
      def self.policy
        ATTRIBUTE_SYNC_POLICY
      end
    end

    # This delegate is used for third-party applications.
    class ThirdPartyDelegate < DefaultDelegate
      ATTRIBUTE_SYNC_POLICY = {
        oauth_application: {
          id: :ineligible,
          name: :sync,
          url: :sync,
          key: :sync,
          user_id: :ineligible,
          device_flow_enabled: :sync,
          canonical_avatar_url: :sync,
        },
        application_callback_urls: {
          id: :ineligible,
          url: :sync,
          application_id: :ineligible,
          application_type: :ineligible
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
        owner: {
          dotcom_id: :sync,
          dotcom_type: :sync,
          dotcom_node_id: :sync,
          login: :sync,
          display_login: :sync,
          url: :sync,
          avatar_url: :sync,
        }
      }

      sig { override.returns(T::Hash[Symbol, T::Hash[Symbol, Symbol]]) }
      def self.policy
        ATTRIBUTE_SYNC_POLICY
      end
    end
  end
end
