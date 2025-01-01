# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ActorDeletedBy < Resolvers::Actor
      def async_actor
        object.async_deleted_by
      end
    end
  end
end
