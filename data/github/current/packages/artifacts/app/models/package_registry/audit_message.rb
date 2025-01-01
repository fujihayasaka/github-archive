# typed: false
# frozen_string_literal: true

module PackageRegistry
  # A wrapper around GitHub::StreamProcessors::Message to be used for Packages audit events
  class AuditMessage < SimpleDelegator

    DOCKER = "DOCKER"
    DOCKER_BASE_LAYER = "docker-base-layer"

    # Public: Boolean indicating if this message should not be published to the audit log
    attr_accessor :should_skip

    # Public: The id of the actor who performed the action
    attr_accessor :actor_id

    # Public: The name of the actor who performed the action
    attr_accessor :actor

    # Public: The type of the actor who performed the action
    attr_accessor :actor_type

    # Public: The id of the organization targeted by the action
    attr_accessor :org_id

    # Public: The name of the organization targeted by the action
    attr_accessor :org

    # Public: The id of the repo associated with the package
    attr_accessor :repo_id

    # Public: The name of the repo associated with the package
    attr_accessor :repo

    # Public: The id of the package
    attr_accessor :package_id

    # Public: The name of the package
    attr_accessor :package

    # Public: The ecosystem of the package (NPM, Maven, Docker, etc...)
    attr_accessor :ecosystem

    # Public: The id of the version
    attr_accessor :version_id

    # Public: The name of the version
    attr_accessor :version

    # Public: The number of the versions belonging to a package
    attr_accessor :version_count

    # Public: The amount of storage in bytes used by the package/version
    attr_accessor :storage_bytes

    # Public: Boolean flag indicating whether this is a first publish or a re-publish
    attr_accessor :is_republished

    # Public: The time the package/version was deleted in seconds
    attr_accessor :deleted_at_seconds

    # Public: The nanoseconds when the package/version was deleted
    attr_accessor :deleted_at_nanos

    # Public: Sets the deleted_time to a formatted string (ex: 2020-12-04 14:00:17 -0800)
    attr_writer :deleted_time

    # Public: The time the package/version was published in seconds
    attr_accessor :published_at_seconds

    # Public: The nanoseconds when the package/version was published
    attr_accessor :published_at_nanos

    # Public: Sets the published_time to a formatted string (ex: 2020-12-04 14:00:17 -0800)
    attr_writer :published_time

    # Public: Initialize the AuditMessage
    #
    # Pass a block when invoking this function to initialize the instance variables
    #
    # example:
    #
    #   AuditMessage.new(original_message) do |msg|
    #     msg.actor_id = msg.get(:actor, :id)
    #     msg.actor = msg.get(:actor, :login)
    #     msg.org_id = msg.get(:package, :owner_org, :id)
    #     msg.org = msg.get(:package, :owner_org, :login)
    #     msg.repo_id = msg.get(:package, :repository, :id)
    #     msg.repo = msg.get(:package, :repository, :name)
    #     msg.package_id = msg.get(:package, :id)
    #     msg.package = msg.get(:package, :name)
    #     msg.ecosystem = msg.get(:package, :registry_type)
    #     msg.version_id = msg.get(:version, :id)
    #     msg.version = msg.get(:version, :version)
    #     msg.deleted_at_seconds = msg.get(:deleted_at, :seconds)
    #     msg.deleted_at_nanos = msg.get(:deleted_at, :nanos)
    #   end
    #
    # message - The original GitHub::StreamProcessors::Message message
    def initialize(message)
      super
      yield(self)
    end

    # Public: Retrieves the value for the given keys from the message.value hash
    #
    # If the given keys are not found and skip_if_missing is true the message will be marked as skipped
    #
    # keys - A sequence nested keys
    # skip_if_missing - Boolean flag that determines is a message is marked as skipped if the given keys are not found (defaults to true)
    #
    # Returns the value of the specified keys, or nil if the keys are not found
    def get(*keys, skip_if_missing: true)

      if (val = self.value.dig(*keys)).nil? && skip_if_missing && !self.skipped?
        self.skip("missing_#{keys.join("_")}")
      end

      val
    end

    # Public: The deleted at time formatted as a string (ex: 2020-12-04 14:00:17 -0800)
    #
    # Returns deleted at time as a string
    def deleted_time
      @deleted_time ||= ::PackageRegistry::Instrumentation.format_time(
        seconds: @deleted_at_seconds,
        nanos: @deleted_at_nanos
      )
    end

    # Public: The published at time formatted as a string (ex: 2020-12-04 14:00:17 -0800)
    #
    # Returns published at time as a string
    def published_time
      @published_time ||= ::PackageRegistry::Instrumentation.format_time(
        seconds: @published_at_seconds,
        nanos: @published_at_nanos
      )
    end

    # Public: Whether or not the version is a docker-base-layer
    #
    # Returns Boolean
    def docker_base_layer?
      DOCKER.casecmp?(@ecosystem.to_s) && @version == DOCKER_BASE_LAYER
    end

    # Public: Whether or not the message was skipped
    #
    # Returns Boolean
    def skipped?
      self.skip("message explicitly skipped") if self.should_skip
      self.skip("internal_version") if self.docker_base_layer?
      super
    end

  end
end
