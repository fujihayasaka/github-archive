# typed: true
# frozen_string_literal: true

module GitHub
  extend T::Helpers

  # An interface for objects that can be used as actors in flipper, but do not extend GitHub::FlipperActor
  #
  # **NOTE** Prefer including FlipperActor directly in your class, rather than using this interface.
  module IFlipperActor
    extend T::Helpers

    requires_ancestor { Kernel }

    interface!

    # Internal: The ID stored by Flipper for this actor to enable per-actor or
    # percent-of-actors enabling of features.
    sig { abstract.returns(String) }
    def flipper_id; end

    # Public: Get the hash of memoized custom gates for this actor.
    sig { abstract.returns(T::Hash[String, T::Boolean]) }
    def memoized_custom_gates; end
  end

  module FlipperActor
    extend T::Helpers

    include IFlipperActor

    # Private: Used to server as a separator between the class name and the id for
    # flipper actors (ie: User:1).
    FLIPPER_ID_SEPARATOR = ":".freeze
    # Use lookahead/lookbehind to allow class names on the right hand side of
    # the separator:
    FLIPPER_ID_PATTERN = /(?<!:):(?!:)/

    # Public: Given a flipper_id converts it to a github domain instance
    # (ie: "User:235" => User.find_by_id(235)).
    def self.from_flipper_id(flipper_id)
      model_name, id = flipper_id_to_parts(flipper_id)
      model_name.constantize.find_by_id(id)
    end

    # Public: Given a flipper_id it returns the class name
    # (ie: "User:235" => "User").
    def self.class_name_from_flipper_id(flipper_id)
      flipper_id_to_parts(flipper_id).first
    end

    # Public: Given a flipper_id it returns the id
    # (ie: "User:235" => "235").
    def self.id_from_flipper_id(flipper_id)
      flipper_id_to_parts(flipper_id).last
    end

    # Public: Returns the class name and id when given a flipper_id
    # (ie: "User:235" => ["User", "235"]).
    def self.flipper_id_to_parts(flipper_id)
      unless FLIPPER_ID_PATTERN =~ flipper_id
        raise ArgumentError, "flipper_id #{flipper_id} must include #{FLIPPER_ID_SEPARATOR}"
      end

      class_name, _, id = flipper_id.rpartition(FLIPPER_ID_PATTERN)
      [class_name, id]
    end

    # Public: Get the actor based on the display name.
    # When overriding `actor_display_name`, this method should include a when case to provide the necessary reverse query to find the actor by name.
    # Deprecated
    def self.old_from_actor_display_name(type, name)
      case type
      when "User"
        return User.find_by_login name
      when "Bot"
        return Bot.find_by_login name
      when "Organization"
        return Organization.find_by_login name
      when "Business"
        return Business.find_by(slug: name)
      when "Repository"
        return Repository.with_name_with_owner name
      when "MemexProject"
        return MemexProject.find_with_actor_display_name(name)
      end

      # default implementation assumes name == flipper_id, but that means it must start with the type and separator
      if name.starts_with?("#{type}#{FLIPPER_ID_SEPARATOR}")
        begin
          return from_flipper_id(name)
        rescue NameError
          GitHub.logger.info("Actor type is not valid.", "gh.actor.type" => type)
          return nil
        end
      end

      # otherwise we don't know how to find the actor
      GitHub.logger.info(
        "Unable to find actor from display name. Either actor type is missing from the case statement in GitHub::FlipperActor.from_actor_display_name or the actor display name provided is not a flipper_id.",
        "gh.actor.type" => type
      )
      nil
    end

    # Public: enable a feature for this actor
    #
    # Returns result of Feature::DSL#enable_actor
    def enable_feature(feature_name)
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.flipper[feature_name].enable_actor(self) # rubocop:disable GitHub/FeatureManagement/NoFeatureFlagManipulation
      end
      @memoized_features.delete(feature_name) if @memoized_features
    end

    # Public: disable a feature for this actor
    #
    # Returns result of Feature::DSL#enable_actor
    def disable_feature(feature_name)
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.flipper[feature_name].disable_actor(self) # rubocop:disable GitHub/FeatureManagement/NoFeatureFlagManipulation
      end
      @memoized_features.delete(feature_name) if @memoized_features
    end

    # Public: A universal actor feature checker. If you need to add a method
    # to the actor model that does a feature flag check on actor
    # instances, please use this method rather than adding a new method specific
    # to your feature flag
    #
    sig { params(feature_name: T.any(Symbol, String), memoize: T::Boolean).returns(T::Boolean) }
    def feature_enabled?(feature_name, memoize: true)
      feature_name = feature_name.to_sym
      if memoize
        @memoized_features ||= {}
        return @memoized_features[feature_name] if @memoized_features.key?(feature_name)
        return @memoized_features[feature_name] = GitHub.flipper.feature(feature_name).enabled?(self)
      end
      GitHub.flipper.feature(feature_name).enabled?(self)
    end

    # Internal: The ID stored by Flipper for this actor to enable per-actor or
    # percent-of-actors enabling of features.
    sig { override.returns(String) }
    def flipper_id
      "#{T.unsafe(self).class.name}#{FLIPPER_ID_SEPARATOR}#{T.unsafe(self).id}"
    end

    # Public: Get the hash of memoized custom gates for this actor.
    sig { override.returns(T::Hash[String, T::Boolean]) }
    def memoized_custom_gates
      @memoized_custom_gates ||= T.let({}, T.nilable(T::Hash[String, T::Boolean]))
    end
  end
end
