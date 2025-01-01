# typed: true
# frozen_string_literal: true

class ProximaAppRequest
  module AttributeResolution

    DelegateNotFound = Class.new(RuntimeError)

    def self.delegate(app:)
      delegate_name = if Apps::Privileged.capable?(:proxima_first_party_sync, app: app)
        # If the app is a first-party app, we use the delegate they set in their properties
        Apps::Privileged.property(:proxima_sync_delegate, app: app)
      elsif app.syncable_to_proxima?
        :ThirdPartyDelegate
      end

      parent = T.must(
                case app
                when Integration
                  IntegrationAttributeResolutionDelegates
                when OauthApplication
                  OauthApplicationAttributeResolutionDelegates
                end
              )

      raise DelegateNotFound, "No delegate found for #{app.class} with ID #{app.id}" unless delegate_name.present?

      parent.const_get(delegate_name)
    end

    module BaseDelegate
      extend T::Helpers

      abstract!

      sig { abstract.params(app: T.untyped, attribute: Symbol, stamp: T.nilable(String)).void }
      def synchronizable_attribute_value(app:, attribute:, stamp: nil); end
    end

    module Resolvers
      extend T::Helpers

      abstract!

      sig { params(app: T.any(Integration, OauthApplication)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def resolve_application_callback_urls(app:)
        attributes = %i[url]
        resolve_attribute_array(scope: app.application_callback_urls, parent: :application_callback_urls, attributes: attributes)
      end

      sig { params(app: Integration).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def resolve_hook(app:)
        hook = app.hook
        return nil unless hook.present?

        attributes = %i[name active confirmed pinned_api_version insecure_ssl url secret content_type]
        resolve_attributes(record: hook, parent: :hook, attributes: attributes)
      end

      sig { params(app: Integration).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def resolve_latest_version(app:)
        latest_version = app.latest_version
        return nil unless latest_version.present?

        attributes = %i[note default_permissions default_events single_file_name]
        resolve_attributes(record: latest_version, parent: :latest_version, attributes: attributes)
      end

      sig { params(app: Integration).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def resolve_integration_install_triggers(app:)
        attributes = %i[install_type path reason deactivated]
        resolve_attribute_array(scope: app.integration_install_triggers, parent: :integration_install_triggers, attributes: attributes)
      end

      sig { params(app: Integration).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def resolve_ip_allowlist_entries(app:)
        attributes = %i[allow_list_value range_from range_to name active]
        resolve_attribute_array(scope: app.ip_allowlist_entries, parent: :ip_allowlist_entries, attributes: attributes)
      end

      sig { params(app: T.any(Integration, OauthApplication)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def resolve_client_secrets(app:)
        attributes = %i[secret_hash secret_last_eight]
        resolve_attribute_array(scope: app.client_secrets, parent: :client_secrets, attributes: attributes)
      end

      sig { params(app: Integration).returns(Integer) }
      def resolve_state(app:)
        resolve_attribute(record: app, parent: :integration, attribute_name: :state_before_type_cast)
      end

      sig { params(app: Integration).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def resolve_public_keys(app:)
        attributes = %i[public_pem]
        resolve_attribute_array(scope: app.public_keys, parent: :public_keys, attributes: attributes)
      end

      def resolve_canonical_avatar_url(app:)
        app.primary_avatar_url
      end

      def resolve_owner(owner:)
        attributes = %i[id type login display_login]
        attributes = resolve_attributes(record: owner, parent: :owner, attributes: attributes)
        attributes[:dotcom_id] = attributes.delete(:id)
        attributes[:dotcom_type] = attributes.delete(:type)
        # these naming differences are a bit unfortunate but map to the database values on proxima
        attributes[:dotcom_node_id] = owner.global_relay_id
        attributes[:avatar_url] = owner.primary_avatar_url
        attributes[:url] = Api::Serializer.send(:html_url, "/#{owner.display_login}")

        attributes
      end

      sig { params(scope: T::Enumerable[T.anything], parent: Symbol, attributes: T::Array[Symbol]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def resolve_attribute_array(scope:, parent:, attributes:)
        scope.map do |record|
          resolve_attributes(record: record, parent: parent, attributes: attributes)
        end
      end

      sig { params(record: T.untyped, parent: Symbol, attributes: T::Array[Symbol]).returns(T::Hash[Symbol, T.untyped]) }
      def resolve_attributes(record:, parent:, attributes:)
        attributes.map do |attribute|
          [attribute, resolve_attribute(record: record, parent: parent, attribute_name: attribute)]
        end.to_h
      end

      sig { params(record: T.untyped, parent: Symbol, attribute_name: Symbol).returns(T.untyped) }
      def resolve_attribute(record:, parent:, attribute_name:)
        policy_key = T.must(policy[parent])[attribute_name]
        return nil if policy_key == :ineligible

        if record.respond_to?("raw_#{attribute_name}") && attribute_name != :login
          return record.send("raw_#{attribute_name}")
        end

        record.send(attribute_name)
      end

      sig { abstract.returns(T::Hash[Symbol, T::Hash[Symbol, Symbol]]) }
      def policy; end
    end
  end
end
