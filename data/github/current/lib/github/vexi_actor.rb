# typed: strict
# frozen_string_literal: true

require "vexi"

module GitHub
  module VexiActor
    extend T::Helpers

    include Kernel
    include Vexi::Actor

    # Private: Used to server as a separator between the class name and the id for
    # vexi actors (ie: User:1).
    VEXI_ID_SEPARATOR = T.let(":".freeze, String)
    # Use lookahead/lookbehind to allow class names on the left/right hand side of
    # the separator:
    VEXI_ID_PATTERN = /(?<!:):(?!:)/

    module ClassMethods
      extend T::Helpers

      include Kernel

      # Public: Given an actor name, returns the actor instance.
      # If overridden, feature_flag_actor_name must also be overridden to provide complementary functionality.
      # Note: If you are including GitHub::VexiActor directly in your class, this method can be overridden directly, for example:
      # ```
      # sig { override.params(name: String).returns(T.nilable(GitHub::VexiActor)) }
      # def self.from_feature_flag_actor_name(name)
      #   ... custom implementation here ...
      # end
      # ```
      # However, if you are wanting to override from another included module
      # then you will need to "override" it via class methods that extend the base class using mixes_in_class_methods
      sig { overridable.params(name: String).returns(T.nilable(Vexi::Actor)) }
      def from_feature_flag_actor_name(name)
        VexiActor.from_feature_flag_actor_name(name)
      end
    end

    mixes_in_class_methods(ClassMethods)

    # Public: Given an actor name, returns the actor instance.
    sig { params(name: String).returns(T.nilable(Vexi::Actor)) }
    def self.from_feature_flag_actor_name(name)
      model_name, id = vexi_id_to_parts(name)

      klass = model_name.safe_constantize
      unless klass
        raise ArgumentError, "actor_name #{name} does not start with a valid VexiActor class name"
      end

      klass.find_by_id(id)
    end

    # Public: Validates that a class name follows Ruby constant naming conventions
    # A valid Ruby class name must:
    # - Start with an uppercase letter
    # - Contain only alphanumeric characters, underscores, and :: for namespacing
    # - Each namespace component must start with an uppercase letter
    sig { params(class_name: String).returns(T::Boolean) }
    def self.valid_ruby_class_name?(class_name)
      return false if class_name.empty?
      return false if class_name.start_with?("::") || class_name.end_with?("::")

      # Check for multiple consecutive :: (like :::)
      return false if class_name.include?(":::")

      components = class_name.split("::")
      return false if components.empty?
      return false if components.any?(&:empty?)

      components.all? { |component| component.match?(/\A[A-Z][a-zA-Z0-9_]*\z/) }
    end

    # Public: Given a vexi_id it first checks to see if the class is a non-ActiveRecord class
    # and if it is then it would call its override method from_vexi_id otherwise it would check
    # if the class is part of ActiveRecord and that it has the method find_by_id to call otherwise
    # it raises an argument error. This method converts it to a github domain instance.
    # (ie: "User:235" => User.find_by_id(235)).
    sig { params(vexi_id: String).returns(T.nilable(Vexi::Actor)) }
    def self.from_vexi_id(vexi_id)
      model_name, id = self.vexi_id_to_parts(vexi_id)

      # Validate the class name before attempting constantize
      unless valid_ruby_class_name?(model_name)
        raise ArgumentError, "Invalid class name in vexi_id: #{model_name}"
      end

      klass = model_name.safe_constantize
      unless klass
        raise NameError, "uninitialized constant #{model_name}"
      end

      if klass.respond_to?(:find_by_id)
        klass.find_by_id(id)
      else
        raise ArgumentError, "#{model_name} must respond to find_by_id to find the actor."
      end
    end

    # Public: Generate the actor id.
    sig { params(class_name: T.untyped, id: T.any(String, Integer)).returns(String) }
    def self.to_feature_flag_id(class_name, id)
      "#{class_name}#{VEXI_ID_SEPARATOR}#{id}"
    end

    # Public: Given a vexi_id it returns the id
    # (ie: "User:235" => "235").
    sig { params(vexi_id: String).returns(String) }
    def self.id_from_feature_flag_id(vexi_id)
      # vexi_id_to_parts throws if the vexi_id cannot be split. Therefore, we can safely assume
      # that the last part will always exist.
      vexi_id_to_parts(vexi_id).last
    end

    # Public: Given a vexi_id it returns the class name
    # (ie: "User:235" => "User").
    sig { params(vexi_id: String).returns(String) }
    def self.class_name_from_feature_flag_id(vexi_id)
      vexi_id_to_parts(vexi_id).first
    end

    # Public: Groups actor IDs by the class through which the actor was granted access to the named feature.
    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Can raise if an error occurs when fetching the feature flag, but will return an empty result if the feature flag does not exist.
    #
    # Returns an Array of tuples, where each tuple is of the form [Class, [String]] e.g.
    # [[User, ["123", "456"]], [Organization, ["789"]]].
    sig { params(feature_flag: T.any(String, Symbol)).returns(T::Array[[T.any(T.class_of(Object), String), T::Array[String]]]) }
    def self.actor_ids_by_class_or_raise(feature_flag)
      actor_values = FeatureFlag.vexi.actors_value_or_raise(feature_flag) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      actor_id_parts = actor_values.collect { |actor_value| vexi_id_to_parts(actor_value) }
      grouped_actors = actor_id_parts.group_by { |parts| parts.first }

      grouped_actors.map do |actor_class, actors|
        ids = actors.map { |(_, id)| id }

        begin
          klass = T.cast(actor_class.constantize, T.class_of(Object))
        rescue NameError
        end

        [klass || actor_class, ids]
      end
    end

    # Public: Get the actor type.
    sig { returns(String) }
    def vexi_actor_type
      T.unsafe(self).class.name
    end

    # Public: The ID stored by Vexi for this actor to enable per-actor or
    # percent-of-actors enabling of features.
    sig { returns(String) }
    def vexi_id
      # The default implementation of this method requires that the actor class has an id property
      # If not, the expectation is this method is overridden in the class
      # We will emit a metric for tracking
      unless T.unsafe(self).respond_to?(:id)
        tags = ["class_name:#{T.unsafe(self).class.name}"]
        GitHub.dogstats.increment("gh.vexi.actor.missing_vexi_id.count", tags: tags)

        # Temporary solution to fall back to flipper_id for actors that have that.
        if T.unsafe(self).respond_to?(:flipper_id)
          return T.unsafe(self).flipper_id
        end

        raise ArgumentError, "#{T.unsafe(self).class.name} does not have a vexi_id or id method."
      end
      "#{vexi_actor_type}#{VEXI_ID_SEPARATOR}#{T.unsafe(self).id}"
    end

    # Public: Get the hash of memoized custom gates for this actor.
    sig { returns(T::Hash[String, T::Boolean]) }
    def memoized_custom_gates
      @memoized_custom_gates ||= T.let({}, T.nilable(T::Hash[String, T::Boolean]))
    end

    # Public: Enables a feature flag for this actor.
    #
    # feature_name - The name of the feature flag to enable
    sig { params(feature_name: T.any(Symbol, String)).void }
    def enable_feature_flag(feature_name)
      feature_name = feature_name.to_s
      FeatureFlag.vexi_management.add_feature_flag_actors(feature_name, [self]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
      @memoized_feature_flags.delete(feature_name) if @memoized_feature_flags
    end

    # Public: disable a feature for this actor
    #
    # feature_name - The name of the feature flag to disable
    sig { params(feature_name: T.any(Symbol, String)).void }
    def disable_feature_flag(feature_name)
      feature_name = feature_name.to_s
      FeatureFlag.vexi_management.remove_feature_flag_actors(feature_name, [self]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
      @memoized_feature_flags.delete(feature_name) if @memoized_feature_flags
    end

    # Public: clear memoization of a feature flag for this actor
    #
    # feature_name - The name of the feature flag to disable
    sig { params(feature_name: T.any(Symbol, String)).void }
    def clear_feature_flag_memoization(feature_name)
      feature_name = feature_name.to_s
      FeatureFlag.vexi.clear_feature_flag_memoization(feature_name)
      @memoized_feature_flags.delete(feature_name) if @memoized_feature_flags
    end

    # Public: Returns the result of a feature flag check for this actor.
    #
    # This method will raise errors if the feature check fails.
    # Use `feature_flag_enabled?` if you want built in error handling with a default fallback value.
    #
    # feature_name - The name of the feature flag to check
    #
    # Returns true if the feature is enabled, false if not enabled.
    # Raises StandardError if the feature check fails.
    sig { params(feature_name: T.any(Symbol, String), memoize: T::Boolean).returns(T::Boolean) }
    def feature_flag_enabled_or_raise?(feature_name, memoize: true)
      feature_name = feature_name.to_s
      if memoize
        result = memoized_feature_flag_result(feature_name, false)
        raise T.must(result.error) if result.error
        return result.result
      end
      ::FeatureFlag.vexi.enabled_or_raise?(feature_name, self) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    # Public: Returns the result of a feature flag check for this actor.
    #
    # feature_name - The name of the feature flag to check
    # default - The default value to return if the feature check fails
    # memoize - Whether to memoize the result of the feature flag check (default: true)
    #
    # Returns true if the feature is enabled, false if not enabled, or the default value if the check fails.
    sig { params(feature_name: T.any(Symbol, String), default: T::Boolean, memoize: T::Boolean).returns(T::Boolean) }
    def feature_flag_enabled?(feature_name, default:, memoize: true)
      feature_name = feature_name.to_s
      return memoized_feature_flag_result(feature_name, default).result if memoize
      ::FeatureFlag.vexi.enabled?(feature_name, self, default: default)
    end

    # Public: Get the tenant for the actor.
    # This should be overwritten by any class that includes this module to provide meaningful tenant information.
    sig { overridable.returns(T.nilable(FeatureManagement::ActorTenant)) }
    def actor_tenant
      nil
    end

    # Public: Get the lookup name for the vexi actor.
    # This should be overridden by any class that includes this module to provide a meaningful lookup name.
    # When overriding, `self.from_feature_flag_actor_name` method also needs to be updated with a case for the reverse logic.
    sig { overridable.returns(String) }
    def feature_flag_actor_name
      "#{T.unsafe(self).class.name}#{VEXI_ID_SEPARATOR}#{T.unsafe(self).id}"
    end

    private

    # Private: Returns a memoized feature flag evaluation result for the given feature name.
    # If the result is not already memoized, evaluates the feature flag and memoizes the result.
    #
    # feature_name - The name of the feature flag to check
    # default - The default value to return if the feature flag check fails
    #
    # Returns an EvaluationResult object with the feature flag status.
    sig { params(feature_name: String, default: T::Boolean).returns(::Vexi::EvaluationDetails) }
    def memoized_feature_flag_result(feature_name, default)
      @memoized_feature_flags ||= T.let({}, T.nilable(T::Hash[String, ::Vexi::EvaluationDetails]))

      existing_value = @memoized_feature_flags[feature_name]
      return existing_value if existing_value

      @memoized_feature_flags[feature_name] = ::FeatureFlag.vexi.enabled_with_details(feature_name, self, default: default)
    end

    # Private: Returns the class name and id when given a vexi_id
    # (ie: "User:235" => ["User", "235"]).
    sig { params(vexi_id: String).returns([String, String]) }
    def self.vexi_id_to_parts(vexi_id)
      raise ArgumentError, "vexi_id cannot be empty" if vexi_id.empty?
      raise ArgumentError, "vexi_id #{vexi_id} must include #{VEXI_ID_SEPARATOR}" unless VEXI_ID_PATTERN =~ vexi_id

      class_name, _, id = vexi_id.rpartition(VEXI_ID_PATTERN)
      [class_name, id]
    end

    private_class_method :vexi_id_to_parts
  end
end
