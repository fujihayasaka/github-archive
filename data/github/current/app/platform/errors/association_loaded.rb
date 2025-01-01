# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class AssociationLoaded < Errors::Internal
      def initialize(association_name, object_name)
        message = "Loaded `#{association_name}` association on `#{object_name}`."

        super(message)
      end
    end
  end
end
