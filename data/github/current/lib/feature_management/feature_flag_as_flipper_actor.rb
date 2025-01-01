# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagAsFlipperActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    sig { returns(String) }
    attr_reader :name

    sig { params(name: String).void }
    def initialize(name)
      @name = T.let(name, String)
    end

    # For the FlipperActor module. The ID stored by Flipper for this actor to enable per-actor or
    # percent-of-actors enabling of features.
    sig { override.returns(String) }
    def flipper_id
      "#{T.unsafe(self).class.name}:#{T.unsafe(self).name}"
    end

    # For the FlipperActor module. Get the lookup name for the flipper actor.
    # This should be overridden by any class that includes this module to provide a meaningful lookup name.
    # When overriding, `self.from_flipper_actor_name` method also needs to be updated with a case for the reverse logic.
    sig { override.returns(String) }
    def flipper_actor_name
      "#{T.unsafe(self).class.name}:#{T.unsafe(self).name}"
    end

    # Public: Given an actor name, returns the actor instance.
    sig { override.params(name: String).returns(T.nilable(FeatureFlagAsFlipperActor)) }
    def self.from_flipper_actor_name(name)
      new(name)
    end

    # Public: Given a flipper_id converts it to an actor instance
    sig { params(flipper_id: String).returns(T.nilable(FeatureFlagAsFlipperActor)) }
    def self.from_flipper_id(flipper_id)
      flag_name = self.id_from_flipper_id(flipper_id)
      return nil if flag_name.nil?
      from_flipper_actor_name(flag_name)
    end

    # Public: Given a name converts it to an actor instance. This is called find_by_id to match functonality from
    # the FlipperActor module. Without this, can't add actors via devtools.
    sig { params(name: String).returns(T.nilable(FeatureFlagAsFlipperActor)) }
    def self.find_by_id(name) # rubocop:disable GitHub/FindByDef
      from_flipper_actor_name(name)
    end

    # Public: Gets the display name for the actor.%
    sig { override.returns(T.nilable(String)) }
    def flipper_actor_display_name
      @name
    end

    # Public: Given a flipper_id it returns the id
    sig { params(flipper_id: String).returns(T.nilable(String)) }
    def self.id_from_flipper_id(flipper_id)
      flipper_id.include?(":") ? flipper_id.split(":").last : nil
    end
  end
end
