# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module ConditionExpressionBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include IConditionExpression
    include Kernel

    abstract!

    requires_ancestor { ActiveRecord::Base }

    included do
      T.bind(self, T.all(ConditionExpressionBase::ClassMethods, T.class_of(ActiveRecord::Base)))

      belongs_to :root_condition_expression, class_name: impl_payload.condition_class.name, optional: true
      belongs_to :parent_condition_expression, class_name: impl_payload.condition_class.name, optional: true

      has_many :child_condition_expressions, class_name: impl_payload.condition_class.name, foreign_key: "parent_condition_expression_id", dependent: :delete_all, inverse_of: :parent_condition_expression
      has_many :all_child_condition_expressions, class_name: impl_payload.condition_class.name, foreign_key: "root_condition_expression_id", dependent: :delete_all, inverse_of: :root_condition_expression

      before_save :set_defaults
    end

    sig { abstract.params(value: T.nilable(String)).void }
    def targetable_attribute=(value); end

    sig { abstract.params(value: T.nilable(String)).void }
    def operation=(value); end

    sig { params(value: T.nilable(T.any(String, T::Array[String]))).void }
    def value=(value)
      if value.is_a?(Array)
        super(value.to_json)
      else
        super(value)
      end
    end

    sig { override.returns(T.nilable(T.any(String, T::Array[String]))) }
    def value
      v = super
      if v.is_a?(String)
        begin
          parsed = JSON.parse(v)
          v = parsed if parsed.is_a?(Array)
        rescue JSON::ParserError
          # Not JSON-encoded; treat as a plain string value.
        end
      end
      v
    end

    sig { params(new_expression: IConditionExpression).void }
    def update_from_interface(new_expression)
      self.targetable_attribute = new_expression.targetable_attribute
      self.operation = new_expression.operation
      self.value = new_expression.value
    end

    sig { void }
    def set_defaults
      self.targetable_attribute ||= ""
      self.value ||= ""
    end

    module ClassMethods
      include Kernel

      sig { returns(ImplementationPayload) }
      def impl_payload
        raise NotImplementedError, "#{self.class.name} must implement impl_payload"
      end

      sig { params(condition_expression: IConditionExpression, parent: T.nilable(ConditionExpressionBase), root: T.nilable(ConditionExpressionBase)).returns(ConditionExpressionBase) }
      def create_from_interface(condition_expression, parent = nil, root = nil)
        new_expression = T.cast(self, T.class_of(ActiveRecord::Base)).new
        new_expression.targetable_attribute = condition_expression.targetable_attribute
        new_expression.operation = condition_expression.operation
        new_expression.value = condition_expression.value
        new_expression.root_condition_expression = root
        new_expression.parent_condition_expression = parent

        condition_expression.child_condition_expressions.each do |child|
          new_expression.child_condition_expressions << create_from_interface(child, new_expression, root || new_expression)
        end

        new_expression
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
