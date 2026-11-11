# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module SystemProperties
    module ICustomPropertiesConfigExtension
      extend T::Helpers

      requires_ancestor { ICustomPropertiesConfig }

      abstract!

      sig { abstract.returns(SystemValueModelImpl) }
      def system_value_class; end

      SystemValueModelImpl = T.type_alias do
        T.all(
          T.class_of(ActiveRecord::Base),
          T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::SystemProperties::ValueBase)],
        )
      end
    end
  end
end
