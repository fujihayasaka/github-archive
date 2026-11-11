# typed: strict
# frozen_string_literal: true

module SettingsCore
  class DefaultSettingsProvider < SettingsProvider
    SettingsModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        SettingBase::ClassMethods,
        T::Class[T.all(ActiveRecord::Base, SettingBase)],
      )
    end

    sig { params(name: String, model_class: SettingsModelImpl, attributes_by_models: T::Array[[Targeting::Attribute, String]]).void }
    def initialize(name, model_class, attributes_by_models = [])
      super(name)
      @model_class = model_class
      @attributes_by_models = attributes_by_models
    end

    sig do
      override.params(
        names: T::Array[String],
        targetables: T::Array[Targeting::Targetable],
        cache: T::Hash[String, T.untyped]
      ).returns(T::Array[SettingsCore::ISetting])
    end
    def settings_for(names, targetables, cache = {})
      records = targetables.filter_map do |targetable|
        targetable.internal_record if targetable.internal_record.is_a?(ActiveRecord::Base)
      end
      return [] if records.empty?

      cache_hits = []
      missing_names = Set.new
      missing_records = Set.new
      names.each do |name|
        records.each do |record|
          cache_key = "#{name}/#{record.class.name}/#{record.id}"
          if cache.has_key?(cache_key)
            cache_hits << cache[cache_key]
          else
            missing_names.add(name)
            missing_records.add(record)
          end
        end
      end

      query_settings = if missing_names.any? || missing_records.any?
        results = @model_class
          .where(name: missing_names, resource: missing_records)
          .includes({ rules: [:condition_expression] }).to_ary

        # Populate cache with results
        missing_names.each do |name|
          missing_records.each do |record|
            cache_key = "#{name}/#{record.class.name}/#{record.id}"
            setting = results.find { |s| s.name == name && s.resource == record }
            cache[cache_key] = setting
          end
        end
        results
      else
        []
      end

      settings = (query_settings + cache_hits).compact.uniq
      settings.each do |setting|
        setting.targetable = targetables.find { |t| t.internal_record == setting.resource }
      end
      settings
    end

    sig { override.params(new_settings: T::Array[ISetting], actor: T.nilable(User)).returns(T::Array[ISetting]) }
    def update_settings(new_settings, actor: nil)
      # TODO: Optimize to perform batch updates/inserts
      saved = new_settings.map do |new_setting|
        unless resource = new_setting.targetable&.internal_record.is_a?(ActiveRecord::Base) ? T.must(new_setting.targetable).internal_record : nil
          raise ArgumentError, "Targetable internal_record must be an ActiveRecord::Base"
        end
        existing_setting = new_setting.id ? @model_class.find_by(resource:, id: new_setting.id) : nil
        if existing_setting
          existing_setting.update_from_interface(new_setting)
          reconcile_rules(existing_setting, new_setting.rules)
          # targetable cannot be derived directly from record, so we need to set it explicitly
          existing_setting.targetable = new_setting.targetable
          existing_setting.save ? existing_setting : nil
        else
          # create new setting
          record = new_setting.targetable&.internal_record
          raise ArgumentError, "Targetable does not have a valid internal_record" unless record.is_a?(ActiveRecord::Base)

          saved_setting = @model_class.create_from_interface(new_setting, record)
          # targetable cannot be derived directly from record, so we need to set it explicitly
          saved_setting.targetable = new_setting.targetable
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

    sig { params(existing_setting: SettingBase, new_rules: T::Array[IRule]).returns(T::Array[SettingRuleBase]) }
    def reconcile_rules(existing_setting, new_rules)
      existing_rules = T.cast(existing_setting.rules.to_a, T::Array[SettingRuleBase])
      to_add = new_rules.reject { |r| r.id && existing_rules.any? { |er| er.id == r.id } }
      to_remove = existing_rules.reject { |er| new_rules.any? { |r| r.id == er.id } }
      to_update = existing_rules.select { |r| r.id && new_rules.any? { |er| er.id == r.id } }

      to_add.each do |rule|
        existing_setting.rules << @model_class.rule_class_name.constantize.create_from_interface(rule, existing_setting)
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
        existing_expression.child_condition_expressions << @model_class.rule_class_name.constantize.condition_class_name.constantize.create_from_interface(child, existing_expression, existing_expression.root_condition_expression || existing_expression)
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
