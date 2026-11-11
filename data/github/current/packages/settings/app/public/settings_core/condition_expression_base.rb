# typed: strict
# frozen_string_literal: true

module SettingsCore
  module ConditionExpressionBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include IConditionExpression
    include Kernel

    abstract!

    requires_ancestor { ActiveRecord::Base }

    included do
      T.bind(self, T.all(ConditionExpressionBase::ClassMethods, T.class_of(ActiveRecord::Base)))

      has_one :root_condition_expression, class_name: self.condition_class_name, foreign_key: "root_condition_expression_id", inverse_of: :all_child_condition_expressions
      has_one :parent_condition_expression, class_name: self.condition_class_name, foreign_key: "parent_condition_expression_id", inverse_of: :child_condition_expressions

      has_many :child_condition_expressions, class_name: self.condition_class_name, foreign_key: "parent_condition_expression_id", dependent: :delete_all, inverse_of: :parent_condition_expression
      has_many :all_child_condition_expressions, class_name: self.condition_class_name, foreign_key: "root_condition_expression_id", dependent: :delete_all, inverse_of: :root_condition_expression
    end

    sig { params(new_expression: IConditionExpression).void }
    def update_from_interface(new_expression)
      T.unsafe(self).targetable_attribute = new_expression.targetable_attribute
      T.unsafe(self).operation = new_expression.operation
      T.unsafe(self).value = new_expression.value
    end

    module ClassMethods
      include Kernel

      sig { returns(String) }
      def condition_class_name
        raise NotImplementedError, "#{self.class.name} must implement condition_class_name"
      end

      sig { params(condition_expression: IConditionExpression, parent: T.nilable(ConditionExpressionBase), root: T.nilable(ConditionExpressionBase)).returns(ConditionExpressionBase) }
      def create_from_interface(condition_expression, parent = nil, root = nil)
        new_expression = T.cast(self, T.class_of(ActiveRecord::Base)).new
        new_expression.targetable_attribute = condition_expression.targetable_attribute
        new_expression.operation = condition_expression.operation
        new_expression.value = condition_expression.value
        new_expression.child_condition_expressions = condition_expression.child_condition_expressions.map { |child| create_from_interface(child, new_expression, root ? root : new_expression) }
        new_expression.root_condition_expression = root
        new_expression.parent_condition_expression = parent

        new_expression
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
