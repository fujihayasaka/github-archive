# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class AssociationRefused < Errors::Internal
      def initialize(association_name, object_name, field_name)
        message = <<~MSG
        Refusing to load the `#{association_name}` association on `#{object_name}` while resolving `#{field_name}`!
        Please use `Platform::Loaders` instead.
        For more information, see https://thehub.github.com/engineering/development-and-ops/public-apis/graphql/debugging/common-errors/#associationloaded--associationrefused
        MSG

        super(message)
      end
    end
  end
end
