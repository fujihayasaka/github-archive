# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  module CreateAppJobHelper
    include ProximaAppOwnerHelper
    include ProximaAppHelper

    extend T::Helpers

    abstract!

    LocalStateExists = Class.new(RuntimeError)
    ManifestNotFound = Class.new(RuntimeError)
    UnknownAppType = Class.new(RuntimeError)
    ClientIdCollision = Class.new(RuntimeError)

    sig { params(app_global_relay_id: String).void }
    def perform(app_global_relay_id:)
      # Make sure the app does not already exist
      current_state = ProximaAppSynchronization.find_by(dotcom_global_id: app_global_relay_id)
      raise LocalStateExists if current_state.present?

      manifest = Apps::Privileged::ApiHmacClient.new.app_manifest(id: app_global_relay_id)
      raise ManifestNotFound unless manifest

      raise UnknownAppType, "Unknown app type: #{manifest['type']}" unless manifest["type"] == "Integration" || manifest["type"] == "OauthApplication"

      # Ensure the third-party apps owner exists before creating any third-party apps
      ensure_third_party_apps_owner_exists! if party_type == THIRD_PARTY_TYPE

      existing_app = case manifest["type"]
      when "Integration"
        Integration.find_by(key: manifest["settings"]["key"]) ||
          Integration.find_by(name: manifest["settings"]["name"], owner_id: owner_id, owner_type: "User")
      when "OauthApplication"
        OauthApplication.find_by(key: manifest["settings"]["key"]) ||
          OauthApplication.find_by(name: manifest["settings"]["name"], user_id: owner_id)
      end
      dotcom_owner_metadata = manifest["settings"].delete("owner")

      T.bind(self, T.any(CreateFirstPartyAppJob, CreateThirdPartyAppJob))
      with_write do
        ApplicationRecord::Domain::Integrations.transaction do
          app = if existing_app.present?
            upsert_proxima_app_synchronization_record!(
              app: existing_app,
              dotcom_global_relay_id: app_global_relay_id,
              fingerprint: existing_app.synchronization_fingerprint,
              canonical_avatar_url: manifest["settings"]["canonical_avatar_url"]
            )

            # enqueue the update job if the existing_app.synchronization_fingerprint doesn't match the manifest["fingerprint"]
            if existing_app.synchronization_fingerprint != manifest["fingerprint"]
              update_job = "ProximaAppSync::Update#{party_type.capitalize}PartyAppJob".constantize
              update_job.perform_later(app_global_relay_id, manifest["fingerprint"])
            end

            existing_app
          else
            created_app = case manifest["type"]
            when "Integration"
              create_integration(manifest["settings"])
            when "OauthApplication"
              create_oauth_app(manifest["settings"])
            end

            create_proxima_app_synchronization_record!(
              app: T.must(created_app),
              dotcom_global_relay_id: app_global_relay_id,
              fingerprint: manifest["fingerprint"],
              canonical_avatar_url: manifest["settings"]["canonical_avatar_url"]
            )

            created_app
          end

          if local_owner_metadata = app&.dotcom_app_owner_metadata
            local_owner_metadata.update!(**dotcom_owner_metadata)
          else
            DotcomAppOwnerMetadata.create!(local_app: T.must(app), **dotcom_owner_metadata)
          end
        end
      end
    end

    sig { abstract.returns(String) }
    def party_type; end

    private

    sig { params(app: T.any(Integration, OauthApplication), dotcom_global_relay_id: String, fingerprint: String, canonical_avatar_url: T.untyped).returns(ProximaAppSynchronization) }
    def create_proxima_app_synchronization_record!(app:, dotcom_global_relay_id:, fingerprint:, canonical_avatar_url:)
      ProximaAppSynchronization.create!(
        dotcom_global_id: dotcom_global_relay_id,
        local_app_id: app.id,
        local_app_type: app.class.name,
        fingerprint: fingerprint,
        canonical_avatar_url: canonical_avatar_url
      )
    end

    sig { params(sync_record: ProximaAppSynchronization, dotcom_global_relay_id: String, fingerprint: String, canonical_avatar_url: T.untyped).returns(ProximaAppSynchronization) }
    def update_proxima_app_synchronization_record!(sync_record:, dotcom_global_relay_id:, fingerprint:, canonical_avatar_url:)
      sync_record.update!(
        dotcom_global_id: dotcom_global_relay_id,
        fingerprint: fingerprint,
        canonical_avatar_url: canonical_avatar_url
      )

      sync_record
    end

    sig { params(app: T.any(Integration, OauthApplication), dotcom_global_relay_id: String, fingerprint: String, canonical_avatar_url: T.untyped).returns(ProximaAppSynchronization) }
    def upsert_proxima_app_synchronization_record!(app:, dotcom_global_relay_id:, fingerprint:, canonical_avatar_url:)
      sync_record = ProximaAppSynchronization.find_by(local_app: app)

      if sync_record.present?
        update_proxima_app_synchronization_record!(sync_record:, dotcom_global_relay_id:, fingerprint:, canonical_avatar_url:)
      else
        create_proxima_app_synchronization_record!(app:, dotcom_global_relay_id:, fingerprint:, canonical_avatar_url:)
      end
    end

    sig { params(raw_attributes: T::Hash[T.untyped, T.untyped]).returns(Integration) }
    def create_integration(raw_attributes)
      attributes = build_integration_attributes(raw_attributes)
      Integration.create!(attributes)
    end

    sig { params(raw_attributes: T::Hash[T.untyped, T.untyped]).returns(OauthApplication) }
    def create_oauth_app(raw_attributes)
      attributes = build_oauth_app_attributes(raw_attributes)
      OauthApplication.create!(attributes)
    end

    sig { params(raw_attributes: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    def build_integration_attributes(raw_attributes)
      attributes = {}

      # These hard-coded attribute values are only for first-party apps.
      raw_attributes["owner_id"] = owner_id
      raw_attributes["user_suspended_by_id"] = owner_id if raw_attributes["suspended_at"].present?

      if raw_attributes["latest_version"].present? && raw_attributes["latest_version"]["single_file_name"].nil?
        raw_attributes["latest_version"].delete("single_file_name") # This field cannot be set to nil
      end

      if raw_attributes["client_secrets"].present?
        raw_attributes["client_secrets"].each do |client_secret|
          client_secret["creator_id"] = owner_id
        end
      end

      if raw_attributes["public_keys"].present?
        raw_attributes["public_keys"].each do |public_key|
          public_key["creator_id"] = owner_id
          public_key["skip_generate_key"] = true
        end
      end

      # Add attributes for top-level integration fields
      Integration.attribute_names.each do |attribute_name|
        attributes[attribute_name.to_sym] = raw_attributes[attribute_name] if raw_attributes.key?(attribute_name)
      end

      # Add attributes for nested associations
      attributes[:latest_version_attributes] = raw_attributes["latest_version"] if raw_attributes["latest_version"].present?
      attributes[:application_callback_urls_attributes] = raw_attributes["application_callback_urls"]
      attributes[:hook_attributes] = raw_attributes["hook"] unless raw_attributes["hook"].nil?
      attributes[:integration_install_triggers_attributes] = raw_attributes["integration_install_triggers"]
      attributes[:ip_allowlist_entries_attributes] = raw_attributes["ip_allowlist_entries"]
      attributes[:client_secrets_attributes] = raw_attributes["client_secrets"]
      # We never want to sync public keys for 1P apps on Proxima
      attributes[:public_keys_attributes] = raw_attributes.fetch("public_keys", []) unless party_type == FIRST_PARTY_TYPE

      # The `integrations.public` attribute has been deprecated in favor of
      # `integrations.visibility`, which should be populated on all GitHub Apps
      # (via a data transition).
      #
      # See https://github.com/github/ecosystem-apps/issues/6122.
      attributes.delete(:public)

      attributes
    end

    sig { params(raw_attributes: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    def build_oauth_app_attributes(raw_attributes)
      attributes = {}

      attributes[:user_id] = owner_id

      if raw_attributes["client_secrets"].present?
        raw_attributes["client_secrets"].each do |client_secret|
          client_secret["creator_id"] = owner_id
        end
      end

      # Add attributes for top-level OauthApplication fields
      OauthApplication.attribute_names.each do |attribute_name|
        attributes[attribute_name.to_sym] = raw_attributes[attribute_name] if raw_attributes.key?(attribute_name)
      end

      # Add attributes for nested associations
      attributes[:callback_url] = raw_attributes["application_callback_urls"]&.map { |callback_url| callback_url["url"] }
      attributes[:client_secrets_attributes] = raw_attributes["client_secrets"]

      attributes
    end
  end
end
