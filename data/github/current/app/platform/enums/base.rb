# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class Base < GraphQL::Schema::Enum
      class EnumValue < GraphQL::Schema::EnumValue
        include Platform::Objects::Base::Deprecated
        include Platform::Objects::Base::Visibility
        include Platform::Objects::Base::FeatureFlag
        include Platform::Objects::Base::MobileOnly
        include Platform::Objects::Base::RequiredCapabilities
        include Platform::Objects::Base::MapToService

        def initialize(*args, visibility: nil, feature_flag: nil, mobile_only: nil, **kwargs, &block)
          visibility_from_config(visibility)

          self.feature_flag(feature_flag) if feature_flag
          self.mobile_only(mobile_only) if mobile_only

          super(*T.unsafe(args), **T.unsafe(kwargs), &block)
        end

        def service_mapping(serviceowners: nil)
          owner.service_mapping(serviceowners: serviceowners)
        end

        def visible?(context)
          visibility_from_context(context)
        end
      end
      extend Platform::Objects::Base::MapToService
      extend Platform::Objects::Base::FeatureFlag
      extend Platform::Objects::Base::MobileOnly
      extend Platform::Objects::Base::RequiredCapabilities
      extend Platform::Objects::Base::Visibility

      def self.visible?(context)
        visibility_from_context(context)
      end

      enum_value_class(EnumValue)

      # @return [Array<String>] The possible GraphQL values for this enum
      def self.graphql_values
        values.keys
      end

      # Ensures the given string is properly formatted to be used as an enum value.
      #
      # - str: A String supposed to be used as an enum value.
      #
      # Returns a String that can be used as a enum value.
      def self.convert_string_to_enum_value(str)
        str.parameterize.underscore.upcase
      end

      def self.default_graphql_name
        @default_graphql_name ||= name.split("::").last
      end
    end
  end
end
