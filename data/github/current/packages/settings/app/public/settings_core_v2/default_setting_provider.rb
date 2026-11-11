# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class DefaultSettingProvider < SettingProvider
    extend T::Helpers

    abstract!

    sig { params(name: String, impl_payload: ImplementationPayload).void }
    def initialize(name, impl_payload)
      super(name)
      @impl_payload = impl_payload
    end

    sig do
      override.params(
        targets_to_names: T::Hash[T.untyped, T::Array[String]],
      ).returns(T::Array[SettingsCoreV2::ISetting])
    end
    def settings_for(targets_to_names)
      all_names = targets_to_names.values.flatten.uniq
      records = targets_to_names.keys.filter_map do |resource|
        record = resource.respond_to?(:internal_record) ? resource.internal_record : resource
        record if record.is_a?(ActiveRecord::Base)
      end
      return [] if records.empty?

      @impl_payload.setting_class
        .where(name: all_names, resource: records)
        .includes({ rules: [:condition_expression] }).to_a
    end

    sig { override.params(resource: T.untyped, new_settings: T::Array[ISetting], actor: T.nilable(User)).returns(T::Array[ISetting]) }
    def update_settings(resource, new_settings, actor: nil)
      # Handle SimpleDelegator Copilot::* objects (for now)
      resource = resource.internal_record if resource.respond_to?(:internal_record)

      new_settings = handle_rule_groups(resource, new_settings) if supported_features.include?(Features::RULE_GROUPS)

      # TODO: Optimize to perform batch updates/inserts
      saved = new_settings.map do |new_setting|
        existing_setting = if new_setting.id
          @impl_payload.setting_class.find_by(resource:, id: new_setting.id)
        else
          @impl_payload.setting_class.find_by(resource:, name: new_setting.name)
        end
        if existing_setting
          existing_setting.update_from_interface(new_setting)
          reconcile_rules(existing_setting, new_setting.rules)
          existing_setting.save ? existing_setting : nil
        else
          saved_setting = @impl_payload.setting_class.create_from_interface(new_setting, resource)
          saved_setting.save ? saved_setting : nil
        end
      end

      saved.compact
    end

    sig { override.returns(T::Array[Features]) }
    def supported_features
      [
        Features::WRITE_SETTINGS,
        Features::WRITE_RULES
      ]
    end

    private

    sig { params(resource: T.untyped, new_settings: T::Array[ISetting]).returns(T::Array[ISetting]) }
    def handle_rule_groups(resource, new_settings)
      allowed_condition_ids = @impl_payload.setting_class.where(resource:).joins(:rules).pluck("rules.condition_expression_id").uniq

      conditions = new_settings.flat_map(&:rules).map(&:condition_expression)
      new_conditions = {}
      conditions.filter { |c| (c.id || 0) < 0 }.uniq { |c| c.id }.each do |condition|
        saved_condition = @impl_payload.condition_class.create_from_interface(condition, nil, nil)
        saved_condition.save!
        new_conditions[condition.id] = saved_condition
      end

      new_settings.map do |setting|
        new_rules = setting.rules.map do |rule|
          if new_conditions[rule.condition_expression.id]
            # save a new rule with the new condition ID
            MemoryRule.new(rule.rule_type, rule.parameters, new_conditions[rule.condition_expression.id], id: rule.id, priority: rule.priority)
          elsif rule.condition_expression.id && !allowed_condition_ids.include?(rule.condition_expression.id)
            # save a new condition without the disallowed ID
            cleaned_expression = MemoryConditionExpression.new(rule.condition_expression.targetable_attribute, rule.condition_expression.operation, rule.condition_expression.value, rule.condition_expression.child_condition_expressions)
            MemoryRule.new(rule.rule_type, rule.parameters, cleaned_expression, id: rule.id, priority: rule.priority)
          else
            rule
          end
        end
        MemorySetting.new(setting.name, setting.value, setting.resource, new_rules, id: setting.id)
      end
    end

    sig { params(existing_setting: SettingBase, new_rules: T::Array[IRule]).returns(T::Array[SettingRuleBase]) }
    def reconcile_rules(existing_setting, new_rules)
      existing_rules = T.cast(existing_setting.rules.to_a, T::Array[SettingRuleBase])
      to_add = new_rules.reject { |r| r.id && existing_rules.any? { |er| er.id == r.id } }
      to_remove = existing_rules.reject { |er| new_rules.any? { |r| r.id == er.id } }
      to_update = existing_rules.select { |r| r.id && new_rules.any? { |er| er.id == r.id } }

      to_add.each do |rule|
        existing_setting.rules << @impl_payload.rule_class.create_from_interface(rule, existing_setting)
      end
      to_remove.each do |rule|
        rule.destroy
      end
      to_update.each do |rule|
        new_rule = new_rules.find { |r| r.id == rule.id }
        next unless new_rule
        rule.update_from_interface(new_rule)
        reconcile_condition_expression(T.cast(rule.condition_expression, ConditionExpressionBase), new_rule.condition_expression)
        rule.save!
      end
    end

    sig { params(existing_expression: ConditionExpressionBase, new_expression: IConditionExpression).void }
    def reconcile_condition_expression(existing_expression, new_expression)
      existing_expression.update_from_interface(new_expression)

      existing_children = T.cast(existing_expression.child_condition_expressions.to_a, T::Array[ConditionExpressionBase])
      to_add = new_expression.child_condition_expressions.reject { |ce| ce.id && existing_children.any? { |ec| ec.id == ce.id } }
      to_remove = existing_children.reject { |ec| new_expression.child_condition_expressions.any? { |ce| ce.id == ec.id } }
      to_update = existing_children.select { |ec| ec.id && new_expression.child_condition_expressions.any? { |ce| ce.id == ec.id } }

      to_add.each do |child|
        root = T.cast(existing_expression.root_condition_expression || existing_expression, ConditionExpressionBase)
        existing_expression.child_condition_expressions << @impl_payload.condition_class.create_from_interface(child, existing_expression, root)
      end
      to_remove.each do |child|
        child.destroy
      end
      to_update.each do |child|
        new_child = new_expression.child_condition_expressions.find { |ce| ce.id == child.id }
        next unless new_child
        child.update_from_interface(new_child)
        reconcile_condition_expression(child, new_child)
        child.save!
      end

      existing_expression.save!
    end
  end
end
