# typed: true
# frozen_string_literal: true

# NOTE: This file has some type annotations in sorbet/rbi/shims/platform_interfaces.rbi

module Platform
  module Interfaces
    module Base
      include GraphQL::Schema::Interface
      field_class Objects::Base::Field

      extend T::Helpers
      requires_ancestor { Kernel }

      module BaseDefinitionMethods
        include Platform::Helpers::Url
        include Platform::Objects::Base::MapToService::ClassMethods
        include Platform::Objects::Base::FeatureFlags
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
    end
  end
end
