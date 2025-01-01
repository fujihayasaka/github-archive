# typed: true
# frozen_string_literal: true
module Platform
  module Interfaces
    module Base
      include GraphQL::Schema::Interface
      field_class Objects::Base::Field

      module BaseDefinitionMethods
        include Platform::Helpers::Url
        include Platform::Objects::Base::MapToService
        include Platform::Objects::Base::FeatureFlag
        include Platform::Objects::Base::MobileOnly
        include Platform::Objects::Base::RequiredCapabilities
        include Platform::Objects::Base::LimitActorsTo
        include Platform::Objects::Base::Visibility
        include Platform::Objects::Base::ClassBasedEdgeType
        include Platform::Objects::Base::FieldShortcuts
      end

      # Add helpers to interface definition classes:
      definition_methods do
        include BaseDefinitionMethods

        def visible?(context)
          context[:mask].present? ? !context[:mask].call(self, context) : true
        end
      end

      # For some reason, including this in `definition_methods` above
      # doesn't override MapToServiceForBuiltIns#service_mapping,
      # have to override it here instead, so it will use SERVICEOWNERS
      extend Platform::Objects::Base::MapToService
    end
  end
end
