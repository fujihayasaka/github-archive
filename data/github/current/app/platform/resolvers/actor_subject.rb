# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ActorSubject < Resolvers::Actor
      def async_actor
        object.async_subject
      end
    end
  end
end
