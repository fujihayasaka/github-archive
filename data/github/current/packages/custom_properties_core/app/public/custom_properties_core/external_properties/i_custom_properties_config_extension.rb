# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module ExternalProperties
    module ICustomPropertiesConfigExtension
      extend T::Helpers

      requires_ancestor { ICustomPropertiesConfig }

      abstract!

      sig { abstract.returns(ExternalNamespaceModelImpl) }
      def external_namespace_class; end

      sig { abstract.returns(ExternalDefinitionModelImpl) }
      def external_definition_class; end

      sig { abstract.returns(ExternalValueModelImpl) }
      def external_value_class; end

      ExternalNamespaceModelImpl = T.type_alias do
        T.all(
          T.class_of(ActiveRecord::Base),
          T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::ExternalProperties::NamespaceBase)],
        )
      end

      ExternalDefinitionModelImpl = T.type_alias do
        T.all(
          T.class_of(ActiveRecord::Base),
          T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::ExternalProperties::DefinitionBase)],
        )
      end

      ExternalValueModelImpl = T.type_alias do
        T.all(
          T.class_of(ActiveRecord::Base),
          T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::ExternalProperties::ValueBase)],
        )
      end
    end
  end
end
