# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ActorCreator < Resolvers::Actor
      def async_actor
        object.async_creator
      end
    end
  end
end
