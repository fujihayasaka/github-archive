# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Usages
    module ICustomPropertiesConfigExtension
      extend T::Helpers

      requires_ancestor { ICustomPropertiesConfig }

      abstract!

      sig { abstract.returns(UsageModelImpl) }
      def usage_class; end

      UsageModelImpl = T.type_alias do
        T.all(
          T.class_of(ActiveRecord::Base),
          T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::Usages::IPropertyUsage)],
        )
      end
    end
  end
end
