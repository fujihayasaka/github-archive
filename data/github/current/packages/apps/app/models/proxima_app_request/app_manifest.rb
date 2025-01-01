# typed: strict
# frozen_string_literal: true

# This class is responsible for serializing an App into a manifest
# that can be sent to a Proxima Stamp for synchronization.
class ProximaAppRequest
  class AppManifest
    extend T::Sig

    UnknownAppType = Class.new(StandardError)

    sig { returns(T.any(OauthApplication, Integration)) }
    attr_reader :app

    sig { returns(ProximaAppRequest::AttributeResolution::BaseDelegate) }
    attr_reader :attr_resolution_delegate

    INTEGRATION_ATTRIBUTES = T.let([:name, :url, :description, :public, :slug, :key, :setup_url,
       :bgcolor, :setup_on_update, :deleted_at, :request_oauth_on_install, :user_token_expiration, :state,
       :suspended_at, :user_suspended_by_id, :pinned_api_version, :device_flow_enabled, :public_keys,
       :latest_version, :application_callback_urls, :hook, :integration_install_triggers, :ip_allowlist_entries,
       :client_secrets, :canonical_avatar_url, :owner
    ].freeze, T::Array[Symbol])

    RESTRICTED_INTEGRATION_ATTRIBUTES = T.let([:private_keys].freeze, T::Array[Symbol])

    OAUTH_APPLICATION_ATTRIBUTES = T.let([:name, :url, :key, :device_flow_enabled, :application_callback_urls, :client_secrets, :owner, :canonical_avatar_url].freeze, T::Array[Symbol])

    sig { params(app: T.any(OauthApplication, Integration)).void }
    def initialize(app)
      @app = app
      @attr_resolution_delegate = T.let(
        ProximaAppRequest::AttributeResolution.delegate(app: app),
        ProximaAppRequest::AttributeResolution::BaseDelegate
      )
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def serialize_manifest
      return {} unless app.syncable_to_proxima?

      application = app

      case application
      when Integration
        serialize_integration_manifest
      when OauthApplication
        serialize_oauth_application_manifest
      else
        T.absurd(application)
      end
    end

    private

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def serialize_integration_manifest
      app = T.cast(self.app, Integration)
      INTEGRATION_ATTRIBUTES.map do |attribute|
        raise "Invalid attribute: #{attribute}. See https://thehub.github.com/epd/engineering/products-and-services/dotcom/apps/proxima/how-to-synchronize-apps-on-proxima/ for current best practices." if RESTRICTED_INTEGRATION_ATTRIBUTES.include?(attribute)
        [attribute, attr_resolution_delegate.synchronizable_attribute_value(app: app, attribute: attribute)]
      end.to_h
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def serialize_oauth_application_manifest
      app = T.cast(self.app, OauthApplication)
      OAUTH_APPLICATION_ATTRIBUTES.map do |attribute|
        [attribute, attr_resolution_delegate.synchronizable_attribute_value(app: app, attribute: attribute)]
      end.to_h
    end
  end
end
