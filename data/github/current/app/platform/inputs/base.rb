# typed: true
# frozen_string_literal: true
module Platform
  module Inputs
    class Base < GraphQL::Schema::InputObject
      extend Platform::Objects::Base::MapToService
      extend Platform::Objects::Base::FeatureFlag
      extend Platform::Objects::Base::MobileOnly
      extend Platform::Objects::Base::RequiredCapabilities
      extend Platform::Objects::Base::Visibility
      extend Platform::Objects::Base::MarkForUpcomingTypeChange

      def self.visible?(context)
        visibility_from_context(context)
      end

      argument_class Platform::Objects::Base::Argument
    end
  end
end
