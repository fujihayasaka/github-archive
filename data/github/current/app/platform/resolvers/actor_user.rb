# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ActorUser < Resolvers::Actor
      def async_actor
        object.async_user
      end
    end
  end
end
