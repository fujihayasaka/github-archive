# frozen_string_literal: true
#              

module Vexi
  # Vexi actor interface.
  module Actor
    # get_actor_id attempts to resolve an actor ID from the provided object.
    def self.get_actor_id(actor)
      if actor.nil?
        nil
      elsif actor.is_a?(String)
        actor
      elsif actor.respond_to?(:vexi_id)
        actor.vexi_id
      elsif actor.respond_to?(:flipper_id)
        actor.flipper_id
      end
    end
  end
end
