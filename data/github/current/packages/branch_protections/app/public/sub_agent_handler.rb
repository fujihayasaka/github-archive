# typed: strict
# frozen_string_literal: true

class SubAgentHandler
  RULESET_NAME = T.let("Enterprise Custom Agent Configuration".freeze, String)

  sig { params(business: Business).returns(T.nilable(RepositoryRuleset)) }
  def self.find_subagent_ruleset(business)
    rulesets = business.rulesets.where(target: "push").includes(:rule_configurations, :conditions)
    return if rulesets.empty?

    rulesets.find do |ruleset|
      file_path_rule = ruleset.rule_configurations.find { |rc| rc.rule_type == "file_path_restriction" }
      next if file_path_rule.nil?

      paths = file_path_rule.parameters["restricted_file_paths"]
      next unless paths.include?("agents/*.md") && paths.include?(".github/agents/*.md")

      conditions = ruleset.conditions

      org_condition = conditions.find { |c| c.target == "organization_name" }
      next if org_condition.nil?
      next unless org_condition.parameters["include"] == [RuleEngine::Conditions::OrganizationNameTarget::ALL_PATTERN]

      repo_property_condition = conditions.find { |c| c.target == "repository_name" }
      next if repo_property_condition.nil?
      next unless repo_property_condition.parameters["include"] == ["~ALL"]

      ruleset
    end
  end

  sig { params(business: Business).returns(RepositoryRuleset) }
  def self.create_sub_agent_ruleset(business)
    sub_agent_ruleset = find_subagent_ruleset(business)
    if sub_agent_ruleset.present?
      raise ArgumentError, "Ruleset already exists for this enterprise"
    end

    ruleset_name = RULESET_NAME
    existing_rulesets = business.rulesets.map(&:name).filter { |name| name.start_with?(RULESET_NAME) }
    (1..20).each do |i|
      break unless existing_rulesets.include?(ruleset_name)
      ruleset_name = "#{RULESET_NAME} (#{i})"
    end
    if existing_rulesets.include?(ruleset_name)
      raise ArgumentError, "Too many existing rulesets with the same name"
    end

    RepositoryRuleset.create!(
      source: business,
      name: ruleset_name,
      target: "push",
      enforcement: "enabled",
      rule_configurations: [
        RepositoryRuleConfiguration.new(
          rule_type: "file_path_restriction",
          parameters: {
            "restricted_file_paths" => %w[.github/agents/*.md agents/*.md]
          }
        )
      ],
      conditions: [
        RepositoryRuleCondition.new(
          target: "organization_name",
          parameters: {
            include: [RuleEngine::Conditions::OrganizationNameTarget::ALL_PATTERN],
            exclude: []
          }
        ),
        RepositoryRuleCondition.new(
          target: "repository_name",
          parameters: {
            include: ["~ALL"],
            exclude: [],
          }
        )
      ],
      bypass_actors: [
        EnterpriseOwnerBypassActor.new
      ]
    )
  end
end
