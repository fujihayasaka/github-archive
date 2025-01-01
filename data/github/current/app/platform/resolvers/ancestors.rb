# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Ancestors < Resolvers::Base
      type Connections.define(Objects::Team), null: false

      def resolve
        object.async_organization.then do
          object.ancestors.scoped
        end
      end
    end
  end
end
