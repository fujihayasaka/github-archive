# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems::RulesHelper
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ::ApplicationComponent }

  delegate :repository, to: :@alert
  delegate :rule_name, :rule_id, to: :@event

  memoize def viewer_can_manage_rules?
    SecurityProduct::Permissions::RepoAuthz.new(repository, actor: current_user).can_manage_security_products?
  end

  memoize def repository_rules_path
    return nil unless viewer_can_manage_rules?

    dependabot_rules_path(user_id: repository.owner, repository: repository.name)
  end

  def target_type
    rule = VulnerabilityAlertRule.find_by(id: rule_id)
    return unless rule

    if rule.global?
      "GitHub preset"
    elsif rule.org_target?
      "Organization" # Change when non-orgs get the feature
    elsif rule.repo_target?
      "Repository"
    end
  end

  def show_event_comment?
    rule_name.present?
  end
end
