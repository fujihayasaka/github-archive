# typed: strict
# frozen_string_literal: true

class Integration
  # Coordinates creation of an IntegrationAgentSource separately from
  # Integration to avoid cross-cluster nested transactions.
  #
  # Returns GH::Result.
  # On success, result.ok? is true.
  # On failure, result.error is one of:
  #   - GH::Result::Error::Validation: validation or save failed (errors are on the integration object)
  #   - GH::Result::Error with AgentSourcePersistError exception: Integration saved but IntegrationAgentSource did not
  class AgentSourceCreator
    # Exception indicating Integration saved but IntegrationAgentSource failed to persist.
    class AgentSourcePersistError < StandardError
      sig { void }
      def initialize
        super("Integration was saved but IntegrationAgentSource failed to save")
      end
    end

    # Create a new Integration with an IntegrationAgentSource.
    #
    # integration          - An unsaved Integration instance (already built with params).
    # agent_source_params  - Hash with :repository_id and :commit_oid.
    #
    # Returns a GH::Result.
    sig { params(integration: Integration, agent_source_params: T::Hash[Symbol, T.untyped]).returns(GH::Result[T.untyped]) }
    def self.create_with_agent_source(integration:, agent_source_params:)
      new(integration: integration, agent_source_params: agent_source_params).create_with_agent_source
    end

    # Add an IntegrationAgentSource to an existing Integration.
    #
    # integration          - A persisted Integration instance.
    # agent_source_params  - Hash with :repository_id and :commit_oid.
    #
    # Returns a GH::Result.
    sig { params(integration: Integration, agent_source_params: T::Hash[Symbol, T.untyped]).returns(GH::Result[T.untyped]) }
    def self.add_agent_source(integration:, agent_source_params:)
      new(integration: integration, agent_source_params: agent_source_params).add_agent_source
    end

    # Validate agent_source fields and import errors onto the integration without saving
    #
    # Returns true if agent_source fields are valid, false otherwise.
    sig { params(integration: Integration, agent_source_params: T::Hash[Symbol, T.untyped]).void }
    def self.validate_agent_source(integration:, agent_source_params:)
      new(integration: integration, agent_source_params: agent_source_params).validate_agent_source
    end

    # Create Integration with IntegrationAgentSource
    #   1. Build agent_source
    #   2. Validate integration
    #   3. Validate agent_source except for integration association (since integration isn't saved yet)
    #   4. Apply mandatory agentic permissions
    #   5. Save integration (creates IntegrationVersion with mandatory permissions)
    #   6. Save agent_source with the persisted integration_id
    sig { returns(GH::Result[T.untyped]) }
    def create_with_agent_source
      agent_source = build_agent_source

      # Validate integration
      integration_valid = @integration.valid?

      # Validate agent_source repo/commit only (not integration presence, since it's not saved yet)
      agent_source_valid = validate_agent_source_fields(agent_source)

      unless integration_valid && agent_source_valid
        import_agent_source_errors(agent_source) unless agent_source_valid
        @integration.agent_source = agent_source
        return GH::Result::Error::Validation.new(@integration)
      end

      # Apply mandatory agentic permissions to the version that will be created
      apply_agentic_permissions

      # Save integration (this also saves its IntegrationVersion)
      unless @integration.save
        return GH::Result::Error::Validation.new(@integration)
      end

      # Now save agent_source separately (different cluster)
      agent_source.integration = @integration
      if agent_source.save
        GH::Result::Ok.new(nil)
      else
        import_agent_source_errors(agent_source)
        GH::Result::Error.new(nil, AgentSourcePersistError.new)
      end
    end

    # Add IntegrationAgentSource to existing Integration
    #   1. Build agent_source
    #   2. Validate agent_source
    #   3. Determine if permissions need upgrading - if yes, create new IntegrationVersion with minimum permissions (saved separately)
    #   4. Save agent_source
    sig { returns(GH::Result[T.untyped]) }
    def add_agent_source
      raise ArgumentError, "Integration must be persisted to add an agent source" unless @integration.persisted?

      agent_source = build_agent_source  # standalone, for validation only

      unless validate_agent_source_fields(agent_source)
        import_agent_source_errors(agent_source)
        @integration.build_agent_source(@agent_source_params)
        return GH::Result::Error::Validation.new(@integration)
      end

      unless upgrade_permissions_if_needed
        @integration.errors.add(:base, "Failed to update permissions")
        return GH::Result::Error::Validation.new(@integration)
      end

      agent_source = @integration.build_agent_source(@agent_source_params)
      if agent_source.save
        GH::Result::Ok.new(nil)
      else
        import_agent_source_errors(agent_source)
        GH::Result::Error::Validation.new(@integration)
      end
    end

    # Validate agent_source fields and import errors onto the integration without saving anything.
    sig { void }
    def validate_agent_source
      agent_source = @integration.build_agent_source(@agent_source_params)
      unless validate_agent_source_fields(agent_source)
        import_agent_source_errors(agent_source)
      end
    end

    private

    sig { params(integration: Integration, agent_source_params: T::Hash[Symbol, T.untyped]).void }
    def initialize(integration:, agent_source_params:)
      @integration = integration
      @agent_source_params = agent_source_params
    end

    sig { returns(Copilot::IntegrationAgentSource) }
    def build_agent_source
      Copilot::IntegrationAgentSource.new(@agent_source_params)
    end

    # Validates agent_source fields without the integration association check.
    # In the create flow, integration isn't persisted yet so belongs_to validation would fail.
    # Returns true if valid, false otherwise.
    sig { params(agent_source: Copilot::IntegrationAgentSource).returns(T::Boolean) }
    def validate_agent_source_fields(agent_source)
      agent_source.valid?
      agent_source.errors.delete(:integration)
      agent_source.errors.delete(:integration_id)
      agent_source.errors.empty?
    end

    # Import agent_source errors onto the integration so controllers
    # can render them using existing error display logic.
    sig { params(agent_source: Copilot::IntegrationAgentSource).void }
    def import_agent_source_errors(agent_source)
      agent_source.errors.each do |error|
        @integration.errors.add(:"agent_source.#{error.attribute}", error.message)
      end
    end

    # Apply minimum agentic permissions to the integration's current version
    # so they are included when the integration is saved.
    sig { void }
    def apply_agentic_permissions
      current_permissions = @integration.default_permissions
      AgenticApp.apply_minimum_permissions(current_permissions)
      @integration.default_permissions = current_permissions
    end

    # For existing integrations, check if permissions need upgrading
    # and create a new IntegrationVersion if so.
    # Returns true if no upgrade needed or upgrade saved successfully, false if save failed.
    sig { returns(T::Boolean) }
    def upgrade_permissions_if_needed
      current_permissions = @integration.default_permissions
      upgraded = AgenticApp.apply_minimum_permissions(current_permissions.dup)

      return true if upgraded == current_permissions

      @integration.default_permissions = upgraded
      !!@integration.save
    end
  end
end
