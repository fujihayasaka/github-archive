# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ActorEditor < Resolvers::Actor
      def async_actor
        object.async_editor
      end
    end
  end
end
