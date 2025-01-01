# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class Base < GraphQL::Schema::Scalar
      extend Platform::Objects::Base::Visibility
      include Platform::Objects::Base::MapToService
      def self.visible?(context)
        visibility_from_context(context)
      end
    end
  end
end
