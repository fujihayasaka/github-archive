# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  # Public: Removes content from a dotcom-sourced app manifest that the local Proxima stamp would reject during
  # persistence. Three classes of drops:
  #
  # 1. Permission resources not registered on this stamp (raises "Default permission records resource is not included
  #    in the list" from DefaultIntegrationPermission's `validates_inclusion_of`).
  # 2. Permission resources that are gated behind a per-actor preview feature flag that isn't enabled here (raises
  #    "<resources> are not supported permissions" from IntegrationVersion#validate_preview_permissions_enabled).
  # 3. Event names not in Integration::Events::SUPPORTED_EVENTS (raises from
  #    IntegrationVersion#validate_default_events_are_supported).
  #
  # When anything is dropped, callers should persist the ProximaAppSynchronization record with .sentinel_fingerprint
  # so the periodic SynchronizeJobOrchestrator sees a mismatch on its next pass and re-runs the update against the
  # (potentially updated) local resource registry. This makes the sync self-healing once a previously-unknown resource
  # gets registered or preview flag flipped, without paging on a stamp that may be temporarily behind dotcom.
  #
  # Usage:
  #   if ManifestSanitizer.drop_unknown_attributes(latest_version_attrs, party_type: "first_party", actor: owner)
  #     fingerprint = ManifestSanitizer.sentinel_fingerprint(manifest["fingerprint"])
  #   end
  class ManifestSanitizer
    SENTINEL_FINGERPRINT_PREFIX = "incomplete-"
    # ProximaAppSynchronization#fingerprint is a VARCHAR(64). Keep the sentinel deterministic so re-runs are
    # idempotent while still fitting in the column by truncating the original fingerprint.
    SENTINEL_FINGERPRINT_MAX_LENGTH = 64

    # Public: A fingerprint that will never match a value coming from dotcom, while still being deterministic for a
    # given original fingerprint. The periodic SynchronizeJobOrchestrator compares the local fingerprint against the
    # dotcom fingerprint to decide whether to enqueue an update job, so wrapping the dotcom fingerprint here
    # guarantees the next pass will retry.
    sig { params(dotcom_fingerprint: String).returns(String) }
    def self.sentinel_fingerprint(dotcom_fingerprint)
      T.must("#{SENTINEL_FINGERPRINT_PREFIX}#{dotcom_fingerprint}"[0, SENTINEL_FINGERPRINT_MAX_LENGTH])
    end

    # Public: Removes unknown permission resources, preview permissions not enabled for the actor, and unsupported
    # event names from the latest_version attributes hash IN PLACE.
    #
    # Returns true if anything was dropped, false otherwise. Callers should use .sentinel_fingerprint for the
    # ProximaAppSynchronization record when this returns true.
    sig do
      params(
        latest_version_attrs: T.untyped,
        party_type: String,
        actor: T.untyped,
        integration: T.untyped,
      ).returns(T::Boolean)
    end
    def self.drop_unknown_attributes(latest_version_attrs, party_type:, actor:, integration: nil)
      new(latest_version_attrs, party_type: party_type, actor: actor, integration: integration).drop_unknown_attributes
    end

    sig { params(latest_version_attrs: T.untyped, party_type: String, actor: T.untyped, integration: T.untyped).void }
    def initialize(latest_version_attrs, party_type:, actor:, integration: nil)
      @latest_version_attrs = latest_version_attrs
      @party_type = party_type
      @actor = actor
      @integration = integration
    end

    sig { returns(T::Boolean) }
    def drop_unknown_attributes
      latest_version_attrs = @latest_version_attrs
      return false unless latest_version_attrs.is_a?(Hash)

      dropped_permissions = drop_unknown_permissions(latest_version_attrs)
      dropped_preview_permissions = drop_disabled_preview_permissions(latest_version_attrs)
      dropped_events = drop_unknown_events(latest_version_attrs)

      record_drops(kind: "permission", names: dropped_permissions)
      record_drops(kind: "preview_permission", names: dropped_preview_permissions)
      record_drops(kind: "event", names: dropped_events)

      dropped_permissions.any? || dropped_preview_permissions.any? || dropped_events.any?
    end

    private

    sig { params(latest_version_attrs: T::Hash[T.untyped, T.untyped]).returns(T::Array[String]) }
    def drop_unknown_permissions(latest_version_attrs)
      permissions = latest_version_attrs["default_permissions"]
      return [] unless permissions.is_a?(Hash)

      valid_resources = DefaultIntegrationPermission.valid_resource_types
      dropped = permissions.keys.reject { |key| valid_resources.include?(key.to_s) }
      dropped.each { |key| permissions.delete(key) }
      dropped.map(&:to_s)
    end

    # Private: Drops permission resources that are valid in principle (registered in the resource registry) but gated
    # behind a per-actor preview feature flag that isn't enabled for this stamp's app owner. Mirrors
    # IntegrationVersion#validate_preview_permissions_enabled.
    sig { params(latest_version_attrs: T::Hash[T.untyped, T.untyped]).returns(T::Array[String]) }
    def drop_disabled_preview_permissions(latest_version_attrs)
      return [] if @actor.nil?

      permissions = latest_version_attrs["default_permissions"]
      return [] unless permissions.is_a?(Hash)

      dropped = permissions.keys.reject do |key|
        Permissions::ResourceRegistry.subject_type_enabled_for?(subject_type: key.to_s, actor: @actor,
          integration: @integration)
      end
      dropped.each { |key| permissions.delete(key) }
      dropped.map(&:to_s)
    end

    sig { params(latest_version_attrs: T::Hash[T.untyped, T.untyped]).returns(T::Array[String]) }
    def drop_unknown_events(latest_version_attrs)
      events = latest_version_attrs["default_events"]
      return [] unless events.is_a?(Array)

      supported_events = Integration::Events::SUPPORTED_EVENTS
      dropped, kept = events.partition { |name| !supported_events.include?(name.to_s) }
      latest_version_attrs["default_events"] = kept
      dropped.map(&:to_s)
    end

    sig { params(kind: String, names: T::Array[String]).void }
    def record_drops(kind:, names:)
      return if names.empty?
      GitHub.dogstats.count("proxima_app_sync.unknown_attribute_dropped",
        names.size, tags: ["party_type:#{@party_type}", "kind:#{kind}"])
    end
  end
end
