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

    # Public: Given a vexi_id it first checks to see if the class is a non-ActiveRecord class
    # and if it is then it would call its override method from_vexi_id otherwise it would check
    # if the class is part of ActiveRecord and that it has the method find_by_id to call otherwise
    # it raises an argument error. This method converts it to a github domain instance.
    # (ie: "User:235" => User.find_by_id(235)).
    sig { params(vexi_id: String).returns(Vexi::Actor) }
    def self.from_vexi_id(vexi_id)
      model_name, id = self.vexi_id_to_parts(vexi_id)
      klass = model_name&.constantize
      # Check for non-active record actor types that include MonolithVexiActor and have it call its override method
      if klass.respond_to?(:from_id)
        klass.from_id(vexi_id)
      elsif klass < ActiveRecord::Base && klass.respond_to?(:find_by_id)
        model_name&.constantize.find_by_id(id)
      else
        raise ArgumentError, "#{model_name} is not an ActiveRecord class nor does it include the MonolithVexiActor module."
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

    # Private: Returns the class name and id when given a vexi_id
    # (ie: "User:235" => ["User", "235"]).
    sig { params(vexi_id: String).returns(T::Array[String]) }
    def self.vexi_id_to_parts(vexi_id)
      raise ArgumentError, "vexi_id cannot be empty" if vexi_id.empty?
      raise ArgumentError, "vexi_id #{vexi_id} must include #{VEXI_ID_SEPARATOR}" unless VEXI_ID_PATTERN =~ vexi_id

      class_name, _, id = vexi_id.rpartition(VEXI_ID_PATTERN)
      [class_name, id]
    end

    private_class_method :vexi_id_to_parts
  end
end
