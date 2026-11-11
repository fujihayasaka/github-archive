# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module ICustomPropertiesConfig
    extend T::Helpers
    include Kernel

    abstract!

    sig { abstract.returns(ValueModelImpl) }
    def value_class; end

    sig { abstract.returns(DefinitionModelImpl) }
    def definition_class; end

    # Public: Retrieve the property limits for the given source.
    # If no custom limits are provided, default limits will be used:
    # - number of allowed definitions: 200 items
    # - max length of property value: 75 characters
    # - max length of url property value: 200 characters
    sig { overridable.params(source: CustomPropertiesCore::IPropertySource).returns(PropertyLimits) }
    def limits(source)
      PropertyLimits.new
    end

    # Public: Additional tags to include when tracking operations for the given source.
    sig { overridable.params(source: CustomPropertiesCore::IPropertySource).returns(T.nilable(T::Hash[T.any(String, Symbol), String])) }
    def additional_tracking_tags(source)
      nil
    end

    ValueModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::ValueBase)],
      )
    end

    DefinitionModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        T::Class[T.all(ActiveRecord::Base, CustomPropertiesCore::DefinitionBase)],
      )
    end
  end
end
