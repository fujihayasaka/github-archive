# typed: strict
# frozen_string_literal: true

module CustomProperties
  module ICustomPropertiesConfig
    extend T::Helpers

    abstract!

    sig { abstract.returns(ValueModelImpl) }
    def value_class; end

    sig { abstract.returns(DefinitionModelImpl) }
    def definition_class; end

    sig { overridable.returns(Integer) }
    def definition_limit
      CustomProperties::Public::DEFINITION_LIMIT
    end

    ValueModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        T::Class[T.all(ActiveRecord::Base, CustomProperties::ValueBase)],
      )
    end

    DefinitionModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        T::Class[T.all(ActiveRecord::Base, CustomProperties::DefinitionBase)],
      )
    end
  end
end
