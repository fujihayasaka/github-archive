# typed: true
# frozen_string_literal: true

module Codespaces
  class Environment
    class Type < ActiveModel::Type::Value
      def type
        :json
      end

      def cast_value(value)
        case value
        when String, Hash
          Environment.from_json(value)
        when Environment
          value
        end
      end

      def serialize(value)
        case value
        when Hash
          ActiveSupport::JSON.encode(value)
        when Environment
          value.to_json
        else
          super
        end
      end

      def changed_in_place?(raw_old_value, new_value)
        cast_value(raw_old_value) != new_value
      end
    end

    include Enumerable
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::Serializers::JSON

    attribute :id, :string
    attribute :type, :string
    attribute :friendly_name, :string
    attribute :created, :datetime
    attribute :updated, :datetime
    attribute :owner_id, :string
    attribute :state, :string
    attribute :container_image, :string
    attribute :seed
    attribute :recent_folders
    attribute :active, :datetime
    attribute :location, :string
    attribute :plan_id, :string
    attribute :auto_shutdown_delay_minutes, :integer
    attribute :sku_name, :string
    attribute :sku_display_name, :string
    attribute :last_state_update_reason, :string
    attribute :last_used, :datetime
    attribute :features
    attribute :git_status
    attribute :create_from_prebuild, :boolean
    attribute :container
    attribute :runtime_constraints
    attribute :prebuild_type, :string
    attribute :storage_utilization_in_kb, :integer
    attribute :display_storage_utilization_in_kb, :boolean, default: false
    attribute :failover_details
    attribute :user_controlled_failure_reason
    attribute :using_copilot_workspace_config

    # Add any new ISO8601 formatted times to this array so they are properly
    # converted.
    ISO8601_ATTRS = %w(created updated active last_used)
    ISO8601_ATTRS.each do |attr|
      define_method("#{attr}=") do |value|
        super(Time.iso8601(value)) if value
      end
    end

    # Convenience/more Rails-y accessors for certain VSCS fields
    alias_method :name, :friendly_name
    alias_method :created_at, :created
    alias_method :updated_at, :updated
    alias_method :last_used_at, :last_used

    # create_from_prebuild will signify that we attempted to create a prebuild for a codespace until after the codespace is ready
    # this alias makes that distinction more clear. currently in use by our provisioning hydro event
    alias_method :attempted_from_prebuild, :create_from_prebuild

    attr_reader :json

    # Supports either JSON directly or an already parsed Hash from JSON.
    def self.from_json(value)
      case value
      when String
        Environment.new.from_json(value)
      when Hash
        Environment.new(value)
      end
    end

    def self.allowed_json_keys
      # Allows inbound hash keys to be either underscore or camelCase variations
      @allowed_json_keys ||= (attribute_names + attribute_names.map { |k| k.to_s.camelize(:lower) }).uniq.freeze
    end

    def available?
      state == Vscs::State::AVAILABLE
    end

    def suspended?
      [Vscs::State::SHUTDOWN, Vscs::State::SHUTTING_DOWN].include?(state)
    end

    def suspendable?
      !suspended? && ![Vscs::State::FAILED,
        Vscs::State::PROVISIONING,
        Vscs::State::DELETED,
        Vscs::State::QUEUED].include?(state)
    end

    # Is the environment currently consuming compute resources?
    def consuming_compute?
      Vscs::State::CONSUMING_COMPUTE_STATES.include?(state)
    end

    def already_started?
      Vscs::State::ALREADY_STARTED_STATES.include?(state)
    end

    def failed?
      state == Vscs::State::FAILED
    end

    def branch
      git_status && git_status["branch"].presence
    end
    alias_method :current_branch, :branch

    def commit
      git_status && git_status["commit"].presence
    end
    alias_method :current_commit, :commit

    def commits_ahead
      git_status && git_status["ahead"].to_i
    end

    def commits_behind
      git_status && git_status["behind"].to_i
    end

    def no_git_repo?
      git_status && git_status["noGitRepo"]
    end

    def connection
      self["connection"]
    end

    def container_id
      container && container["id"]
    end

    def allowed_port_privacy_settings
      runtime_constraints && runtime_constraints["allowedPortPrivacySettings"]
    end

    def cascade_token
      self["accessToken"]
    end

    def has_unpushed_changes?
      git_status && git_status["hasUnpushedChanges"]
    end

    def has_connection?
      !!connection
    end

    def has_uncommitted_changes?
      git_status && git_status["hasUncommittedChanges"]
    end

    def auto_push?
      git_status && git_status["autoPush"]
    end

    def storage_utilization_in_gb
      return nil if storage_utilization_is_nil?

      T.must(storage_utilization_in_kb) / (1024.0**2)
    end

    def storage_utilization_is_zero?
      storage_utilization_in_kb == 0
    end

    def storage_utilization_is_nil?
      storage_utilization_in_kb.nil?
    end

    # Allows hash-like access to all values from parsed JSON without having to
    # first dot-access the `json` attribute. Allow Enumerable methods to work
    # by delegating #each to the underlying JSON hash.
    delegate :[], :merge, :each, :blank?, to: :json

    # Allows us to take in the _entire_ JSON payload, store it, and assign
    # ivars if attr_readers are defined for them without having to constantly
    # add new kwargs to the initializer.
    def assign_attributes(new_attributes)
      unless new_attributes.respond_to?(:each_pair)
        raise ArgumentError, "When assigning attributes, you must pass a hash as an argument, #{new_attributes.class} passed."
      end

      # Freeze it to prevent direct modification of the data within the Hash.
      @json = new_attributes.with_indifferent_access.freeze
      # Map from camelCase JSON keys to underscores if necessary for setters
      json.transform_keys { |k| k.to_s.underscore }.each do |k, v|
        if attribute_names.include?(k)
          public_send(:"#{k}=", v)
        end
      end
    end

    # Define equality for better dirty tracking
    def ==(other)
      return super unless other.is_a?(self.class)

      json == other.json
    end

    # Who doesn't like pretty console output?
    def inspect
      if json
        attribute_string = json.map do |name, value|
          case value
          when nil
            "#{name}: nil"
          when String
            "#{name}: \"#{value}\""
          else
            "#{name}: #{value}"
          end
        end.join(", ")
      end
      "#<#{self.class.name} #{attribute_string}>"
    end

    alias attributes= assign_attributes
    # Aliased to [] above to access values directly from JSON payload
    alias read_attribute_for_serialization []

    # This filtered version has unsafe attributes stripped out and is used by
    # `to_json` and thus for serialization to the DB
    def as_json(options = nil)
      filtered_attributes(transformed_attributes(json.as_json(options)))
    end

    # This is an unfiltered version that allows access to the full JSON representation
    # of the environment
    def environment_json
      transformed_attributes(json).to_json
    end

    private

    def transformed_attributes(attributes)
      # Make sure we use camelCase keys like VSCS when we store this data.
      attributes.transform_keys { |k| k.to_s.camelize(:lower) }
    end

    def filtered_attributes(attributes)
      # Filter out all keys from attributes that were not explicitly allowed via
      # the attributes API.
      attributes.with_indifferent_access.slice(*self.class.allowed_json_keys)
    end
  end
end
