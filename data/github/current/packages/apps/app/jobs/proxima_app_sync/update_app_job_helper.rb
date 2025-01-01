# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  module UpdateAppJobHelper
    include ProximaAppOwnerHelper
    include ProximaAppHelper

    extend T::Helpers

    abstract!

    LocalStateNotFound = Class.new(RuntimeError)
    LocalAppNotFound = Class.new(RuntimeError)
    LocalStateCurrentFingerprint = Class.new(RuntimeError)
    UnknownHasManyAssociation = Class.new(RuntimeError)

    sig { params(global_id: String, fingerprint: String).void }
    def perform(global_id, fingerprint)
      current_state = ProximaAppSynchronization.find_by(dotcom_global_id: global_id)
      raise LocalStateNotFound, "Local state not found for #{global_id}" unless current_state

      local_app = current_state.local_app
      raise LocalAppNotFound, "Local app not found for #{global_id}" unless local_app

      if current_state.fingerprint == fingerprint
        raise LocalStateCurrentFingerprint, "Local state fingerprint is already current for #{global_id}"
      end

      client = Apps::Privileged::ApiHmacClient.new
      dotcom_app_state = client.app_manifest(id: global_id)

      canonical_avatar_url = dotcom_app_state["settings"].delete("canonical_avatar_url")
      incoming_dotcom_owner_metadata = dotcom_app_state["settings"].delete("owner")

      T.bind(self, T.any(UpdateFirstPartyAppJob, UpdateThirdPartyAppJob))
      with_write do
        # Ensure the third-party apps owner exists before updating any third-party apps with the 3rd party app owner
        ensure_third_party_apps_owner_exists! if party_type == THIRD_PARTY_TYPE
        apply_updates_to_local_record(local_app, dotcom_app_state["settings"])
        current_state.update!(fingerprint: dotcom_app_state["fingerprint"], canonical_avatar_url: canonical_avatar_url)
        apply_updates_to_dotcom_owner_metadata(local_app, incoming_dotcom_owner_metadata)
      end
    end

    sig { abstract.returns(String) }
    def party_type; end

    private

    sig { params(local_record: T.any(Integration, OauthApplication), updated_attributes: T::Hash[String, T.untyped]).void }
    def apply_updates_to_local_record(local_record, updated_attributes)
      updated_attributes.each do |attribute, value|
        if value.is_a?(Hash)
          synchronize_association(local_record, attribute, value)
        elsif value.is_a?(Array)
          synchronize_has_many_relationship(local_record, attribute, value)
        else
          local_record.public_send("#{attribute}=", value)
        end
      end

      local_record.save!
    end

    sig { params(local_record: T.any(Integration, OauthApplication), attribute: String, updated_value: T::Hash[String, T.untyped]).void }
    def synchronize_association(local_record, attribute, updated_value)
      if updating_integration_version?(local_record, attribute)
        synchronize_version(T.cast(local_record, Integration), updated_value)
      elsif local_record.public_send(attribute)
        local_record.public_send(attribute).update(updated_value)
      else
        local_record.public_send("build_#{attribute}", updated_value)
      end

      local_record.public_send(attribute).save!
    end

    sig { params(local_record: T.any(Integration, OauthApplication), attribute: String, updated_values: T::Array[T::Hash[String, T.untyped]]).void }
    def synchronize_has_many_relationship(local_record, attribute, updated_values)
      case attribute
      when "application_callback_urls"
        sync_records(local_record, updated_values, :application_callback_urls, "url")
      when "ip_allowlist_entries"
        sync_ip_allowlist_entries(local_record, updated_values)
      when "integration_install_triggers"
        sync_integration_install_triggers(T.cast(local_record, Integration), updated_values)
      when "client_secrets"
        sync_client_secrets(local_record, updated_values, :client_secrets, "secret_hash")
      when "public_keys"
        sync_public_keys(local_record, updated_values, :public_keys, "public_pem")
      else
        raise UnknownHasManyAssociation, "Unknown has_many association #{attribute}"
      end
    end

    sig { params(local_record: T.any(Integration, OauthApplication), attribute: String).returns(T::Boolean) }
    def updating_integration_version?(local_record, attribute)
      local_record.is_a?(Integration) && attribute == "latest_version"
    end

    sig { params(local_record: Integration, permissions_and_events: T::Hash[String, T.untyped]).void }
    def synchronize_version(local_record, permissions_and_events)
      # We only want to update the version if there are new changes, since email communications could
      # be sent when we create a new version with PermissionsEditor.
      return unless should_update_version?(local_record, permissions_and_events)

      self.instance_eval do
        with_write do
          Integration::PermissionsEditor.perform(
            integration: local_record,
            permissions_and_events: permissions_and_events,
          )
        end
      end
    end

    sig { params(local_record: Integration, permissions_and_events: T::Hash[String, T.untyped]).returns(T::Boolean) }
    def should_update_version?(local_record, permissions_and_events)
      incoming_version = IntegrationVersion.new(
        integration: local_record,
        default_events: permissions_and_events["default_events"],
        default_permissions: permissions_and_events["default_permissions"],
      )

      if permissions_and_events["single_file_name"].present?
        incoming_version.single_file_name = permissions_and_events["single_file_name"]
      end

      current_version = local_record.latest_version

      diff = IntegrationVersion::Differ.perform(
        old_version: current_version,
        new_version: incoming_version
      )

      !diff.unchanged?
    end

    sig { params(local_record: T.any(Integration, OauthApplication), updated_values: T::Array[T::Hash[String, T.untyped]], association: Symbol, unique_value: String).void }
    def sync_client_secrets(local_record, updated_values, association, unique_value)
      # Fill in the creator_id
      updated_values.each do |client_secret_hash|
        client_secret_hash["creator_id"] = owner_id
      end
      sync_records(local_record, updated_values, :client_secrets, "secret_hash")
    end

    sig { params(local_record: T.any(Integration, OauthApplication), updated_values: T::Array[T::Hash[String, T.untyped]], association: Symbol, unique_value: String).void }
    def sync_public_keys(local_record, updated_values, association, unique_value)
      # We never want to update the public keys for first-party apps on Proxima
      return if party_type == FIRST_PARTY_TYPE

      # Fill in the creator_id
      updated_values.each do |public_key_hash|
        public_key_hash["creator_id"] = owner_id
        public_key_hash["skip_generate_key"] = true
      end
      sync_records(local_record, updated_values, :public_keys, "public_pem")
    end

    # This method assumes the `allow_list_value` value is unique per app
    sig { params(local_record: T.any(Integration, OauthApplication), updated_values: T::Array[T::Hash[String, T.untyped]]).void }
    def sync_ip_allowlist_entries(local_record, updated_values)
      sync_records(local_record, updated_values, :ip_allowlist_entries, "allow_list_value")
    end

    # This method assumes the `install_type` value is unique per app
    sig { params(local_record: Integration, updated_values: T::Array[T::Hash[String, T.untyped]]).void }
    def sync_integration_install_triggers(local_record, updated_values)
      sync_records(local_record, updated_values, :integration_install_triggers, "install_type")
    end

    # Method to sync has_many associations
    sig { params(local_record: T.any(Integration, OauthApplication), updated_values: T::Array[T::Hash[String, T.untyped]], association: Symbol, unique_value: String).returns(T.any(Integration, OauthApplication)) }
    def sync_records(local_record, updated_values, association, unique_value)
      updated_values_list = updated_values.map { |value| value[unique_value] }

      local_record.send(association).where.not(unique_value => updated_values_list).destroy_all

      updated_values.each do |value|
        unless local_record.send(association).exists?(unique_value => value[unique_value])
          local_record.send(association).create!(value)
        end
      end

      local_record
    end

    sig { params(local_app: T.any(Integration, OauthApplication), incoming_dotcom_owner_metadata: T::Hash[T.untyped, T.untyped]).void }
    def apply_updates_to_dotcom_owner_metadata(local_app, incoming_dotcom_owner_metadata)
      current_dotcom_owner_metadata = DotcomAppOwnerMetadata.find_by(local_app: local_app)

      if current_dotcom_owner_metadata.present?
        current_dotcom_owner_metadata.assign_attributes(**incoming_dotcom_owner_metadata)
        current_dotcom_owner_metadata.save! if current_dotcom_owner_metadata.changed?
      else
        DotcomAppOwnerMetadata.create!(local_app: local_app, **incoming_dotcom_owner_metadata)
      end
    end
  end
end
