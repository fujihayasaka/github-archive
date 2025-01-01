# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Base < GraphQL::Schema::Union
      extend Platform::Objects::Base::Visibility
      include Platform::Objects::Base::MapToService
      extend Platform::Objects::Base::FeatureFlags
      extend Platform::Objects::Base::RequiredCapabilities
      extend Platform::Objects::Base::ClassBasedEdgeType

      def self.visible?(context)
        visibility_from_context(context)
      end
    end
  end
end
