# typed: true
# frozen_string_literal: true

class EnterpriseTeamBypassActor < RepositoryRulesetBypassActor
  def self.display_type
    "EnterpriseTeam"
  end

  def self.display_name
    "Enterprise teams"
  end

  sig { returns(T.nilable(EnterpriseTeam)) }
  def team
    T.let(actor, T.nilable(EnterpriseTeam))
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String),
      limit: Integer
    )
    .returns(T::Array[EnterpriseTeamBypassActor])
  end
  def self.suggest_bypassers(source, query, limit: 10)
    return [] unless source.is_a?(Business) &&
                     source.enterprise_teams_enabled? &&
                     source.enterprise_rulesets_enterprise_teams_enabled? &&
                     source.enterprise_teams.any?

    bypass_actors = []

    source.enterprise_teams.each do |team_to_add|
      if query.present?
        if team_to_add.name.downcase.start_with?(query)
          bypass_actors.unshift(EnterpriseTeamBypassActor.new(actor: team_to_add))
        elsif team_to_add.name.downcase.include?(query)
          bypass_actors.push(EnterpriseTeamBypassActor.new(actor: team_to_add))
        end
      else
        bypass_actors.push(EnterpriseTeamBypassActor.new(actor: team_to_add))
      end

      limit -= 1
      break if limit <= 0
    end

    bypass_actors
  end

  sig do
    params(
      bypassers: T::Array[EnterpriseTeamBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    allowed_modes = []

    user = actor.is_a?(User) ? actor : actor.owner

    if targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Repository)&.enterprise_rulesets_enterprise_teams_enabled?
      bypassers.group_by { |bypass| bypass.bypass_mode }.each do |mode, team_bypass|
        team_ids = team_bypass.map { |bypass| bypass.actor.id }
        teams = EnterpriseTeam.where(id: team_ids)
        team = teams.find { |team| team.member?(user) }
        allowed_modes << mode if team
      end
    end
    allowed_modes
  end
end
