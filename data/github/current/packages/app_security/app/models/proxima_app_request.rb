# typed: strict
# frozen_string_literal: true

# This class models a request that accepts an array of global relay ids and fingerprints
# it checks to see if the fingerprints match the ones in the database and if the database
# contains updated fingerprints it returns the updated fingerprints to the caller
class ProximaAppRequest
  # An interface provided by both the OAuthApplication and Integration models
  # that allows us to check if the app is capable of syncing with Proxima
  #
  # Sorbet ¯\_(ツ)_/¯
  module ProximaSyncableInterface
    extend T::Helpers

    abstract!

    sig { abstract.returns(String) }
    def global_relay_id; end # rubocop:disable GitHub/UntypedObjectId

    sig { abstract.returns(String) }
    def synchronization_fingerprint; end
  end

  sig { returns(T::Array[ProximaSyncableInterface]) }
  def self.first_party_app_ids_requesting_sync
    return T.must(@first_party_app_ids_requesting_sync) if defined?(@first_party_app_ids_requesting_sync)

    @first_party_app_ids_requesting_sync = T.let([], T.nilable(T::Array[ProximaSyncableInterface]))

    Apps::Privileged::Registry.all_aliases.each do |app_alias|
      app = Apps::Privileged.integration(app_alias) || Apps::Privileged.oauth_application(app_alias)

      next unless Apps::Privileged.capable?(:proxima_first_party_sync, app: app)

      T.must(@first_party_app_ids_requesting_sync) << app
    end

    T.must(@first_party_app_ids_requesting_sync)
  end

  sig { returns(T::Array[ProximaSyncableInterface]) }
  def self.third_party_app_ids_requesting_sync
    return T.must(@third_party_app_ids_requesting_sync) if defined?(@third_party_app_ids_requesting_sync)

    @third_party_app_ids_requesting_sync = T.let([], T.nilable(T::Array[ProximaSyncableInterface]))

    syncable_integrations = Integration.syncable_to_proxima
    syncable_oauth_apps = OauthApplication.syncable_to_proxima

    @third_party_app_ids_requesting_sync = syncable_integrations + syncable_oauth_apps
  end

  sig { params(states: T::Array[T::Hash[String, String]], party_type: String).returns(ProximaAppRequest) }
  def self.from(states, party_type: "first")
    payload = states.map do |app|
      AppState.new(T.must(app["global_relay_id"]), T.must(app["fingerprint"]))
    end

    new(payload, party_type)
  end

  sig { returns(T::Array[AppState]) }
  attr_reader :apps

  sig { returns(String) }
  attr_reader :party_type

  sig { params(apps: T::Array[AppState], party_type: String).void }
  def initialize(apps, party_type)
    @apps = apps
    @party_type = party_type
  end

  # Returns an array of apps that are either:
  # - outdated
  # - marked as syncable in the Internal Apps registry but
  #   not present in the list provided by the stamp.
  # - marked for deletion (keep last)
  sig { returns(T::Array[AppState]) }
  def syncable
    missing + outdated + marked_for_deletion
  end

  sig { returns(T::Boolean) }
  def first_party?
    @party_type == "first"
  end

  sig { returns(T::Array[AppState]) }
  def missing
    apps_requesting_sync = first_party? ? self.class.first_party_app_ids_requesting_sync : self.class.third_party_app_ids_requesting_sync

    apps_requesting_sync.map do |requesting_app|
      found = apps.find { |existing_app| existing_app.global_relay_id == requesting_app.global_relay_id }
      next if found

      AppState.new(requesting_app.global_relay_id, requesting_app.synchronization_fingerprint)
    end.compact
  end

  sig { returns(T::Array[AppState]) }
  def outdated
    outdated_apps = @apps.select(&:outdated?)

    outdated_apps.select do |app|
      application = T.must(app.application)
      first_party? ? application.syncable_first_party_app? : application.syncable_third_party_app?
    end
  end

  sig { returns(T::Array[AppState]) }
  def marked_for_deletion
    return [] unless FeatureFlag.vexi.enabled?(:sync_deletions_to_proxima_apps, default: false)

    @apps.select(&:unavailable?)
  end
end
