# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Base < GraphQL::Schema::Resolver
      argument_class Platform::Objects::Base::Argument
      extend Platform::Objects::Base::MapToService
      include Platform::Helpers::Enterprise

      # Set scopes on the field, instead.
      def self.minimum_accepted_scopes
        []
      end
    end
  end
end
