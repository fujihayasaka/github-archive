# typed: strict
# frozen_string_literal: true

module CustomProperties
  module IPropertyDefinition
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(String) }
    def property_name; end

    sig { abstract.returns(T.nilable(String)) }
    def description; end

    sig { abstract.returns(T.nilable(T::Array[String])) }
    def allowed_values; end

    sig { abstract.returns(String) }
    def value_type; end

    sig { abstract.returns(T::Boolean) }
    def required; end

    sig { abstract.returns(T.nilable(PropertyValue)) }
    def default_value; end

    sig { abstract.returns(String) }
    def values_editable_by; end

    sig { abstract.returns(Integer) }
    def source_id; end

    sig { abstract.returns(String) }
    def source_type; end

    sig { abstract.returns(T::Boolean) }
    def business_source_type?; end

    sig { abstract.returns(T::Boolean) }
    def org_source_type?; end

    sig { abstract.returns(T.nilable(String)) }
    def regex; end

    sig { abstract.returns(T::Boolean) }
    def true_false_value_type?; end

    sig { abstract.returns(T::Boolean) }
    def string_value_type?; end

    sig { abstract.returns(T::Boolean) }
    def single_select_value_type?; end

    sig { abstract.returns(T::Boolean) }
    def multi_select_value_type?; end

    sig { abstract.returns(CustomProperties::IPropertySource) }
    def source; end
  end
end
