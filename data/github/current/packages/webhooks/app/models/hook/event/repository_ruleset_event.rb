# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryRulesetEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Repository ruleset created, deleted or edited."

  event_attr :action, :repository_ruleset_id, required: true
  event_attr :changes, :actor_id

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def repository_ruleset
    @repository_ruleset ||= RepositoryRuleset.includes(:source, :rule_configurations, :conditions).find_by(id: repository_ruleset_id)
  end

  def target_repository
    return nil unless repository_ruleset&.source.is_a?(Repository)

    repository_ruleset.source
  end

  def target_organization
    if repository_ruleset&.source.is_a?(User)
      repository_ruleset.source
    elsif repository_ruleset&.source.is_a?(Business)
      nil
    elsif repository_ruleset&.source&.owner.is_a?(Organization)
      repository_ruleset.source.owner
    end
  end

  def deliverable?
    repository_ruleset.present? && (target_repository.present? || target_organization.present?)
  end

  def changes
    return unless changes_attr

    {}.tap do |payload|
      add_ruleset_changes(payload)
      add_rule_changes(payload)
      add_condition_changes(payload)
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def add_ruleset_changes(payload)
    [:name, :enforcement].each do |attr|
      payload[attr] = { from: changes_attr["ruleset_old_#{attr}".to_sym] } if changes_attr.has_key?("ruleset_old_#{attr}".to_sym)
    end
  end

  def add_rule_changes(payload)
    rules_payload = {}

    add_rules_added(rules_payload) if changes_attr.has_key?(:ruleset_rules_added)
    add_rules_updated(rules_payload) if changes_attr.has_key?(:ruleset_rules_updated)
    add_rules_deleted(rules_payload) if changes_attr.has_key?(:deleted_rules)

    payload[:rules] = rules_payload unless rules_payload.empty?
  end

  def add_condition_changes(payload)
    conditions_payload = {}

    add_conditions_added(conditions_payload) if changes_attr.has_key?(:ruleset_conditions_added)
    add_conditions_updated(conditions_payload) if changes_attr.has_key?(:ruleset_conditions_updated)
    add_conditions_deleted(conditions_payload) if changes_attr.has_key?(:deleted_conditions)

    payload[:conditions] = conditions_payload unless conditions_payload.empty?
  end

  def add_conditions_updated(payload)
    payload[:updated] = changes_attr[:ruleset_conditions_updated].map do |condition|
      {
        condition: Api::Serializer.serialize(:repository_rule_condition_hash, repository_ruleset.conditions.find_by(id: condition[:id]), request_source: repository_ruleset.source),
        changes: build_condition_diff(condition)
      }
    end
  end

  def add_rules_updated(payload)
    payload[:updated] = changes_attr[:ruleset_rules_updated].map do |rule|
      {
        rule: Api::Serializer.serialize(:repository_rule_hash, repository_ruleset.rule_configurations.find_by(id: rule[:id])),
        changes: build_rule_diff(rule)
      }
    end
  end

  def build_rule_diff(rule)
    payload = {}

    payload[:rule_type] = { from: rule[:old_rule_type] } if rule[:old_rule_type]
    payload[:pattern] = { from: rule[:old_pattern] } if rule[:old_pattern]
    payload[:configuration] = { from: rule[:old_parameters].to_json } if rule[:old_parameters]

    payload
  end

  def build_condition_diff(condition)
    payload = {}

    payload[:target] = { from: condition[:old_target] } if condition[:old_target]
    payload[:condition_type] = { from: condition[:old_condition_type] } if condition[:old_condition_type]

    return payload unless condition[:old_parameters].present?

    payload[:include] = { from: condition[:old_parameters][:include] } if condition[:old_parameters][:include] != condition[:parameters][:include]
    payload[:exclude] = { from: condition[:old_parameters][:exclude] } if condition[:old_parameters][:exclude] != condition[:parameters][:exclude]

    payload
  end

  def add_rules_added(payload)
    payload[:added] = changes_attr[:ruleset_rules_added].map do |rule|
      Api::Serializer.serialize(:repository_rule_hash, repository_ruleset.rule_configurations.find_by(id: rule[:id]))
    end
  end

  def add_conditions_added(payload)
    payload[:added] = changes_attr[:ruleset_conditions_added].map do |condition|
      Api::Serializer.serialize(:repository_rule_condition_hash, repository_ruleset.conditions.find_by(id: condition[:id]), request_source: repository_ruleset.source)
    end
  end

  def add_rules_deleted(payload)
    payload[:deleted] = changes_attr[:deleted_rules].map { |rule| Api::Serializer.serialize(:repository_rule_hash, rule) }
  end

  def add_conditions_deleted(payload)
    payload[:deleted] = changes_attr[:deleted_conditions].map { |condition| Api::Serializer.serialize(:repository_rule_condition_hash, condition, request_source: repository_ruleset.source) }
  end

end
