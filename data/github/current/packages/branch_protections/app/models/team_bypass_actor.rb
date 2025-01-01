# typed: true
# frozen_string_literal: true

class TeamBypassActor < RepositoryRulesetBypassActor
  def self.display_type
    "Team"
  end

  def self.display_name
    "Team"
  end

  sig { returns(T.nilable(Team)) }
  def team
    T.let(actor, T.nilable(Team))
  end

  sig { returns(T.nilable(String)) }
  def actor_global_relay_id
    team&.global_relay_id
  end

  sig { returns(T.nilable(String)) }
  def actor_preferred_avatar_url
    T.let(team&.primary_avatar_url(20), T.nilable(String))
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      current_user: User,
      query: T.nilable(String),
      filter_repo_results: T::Boolean,
      limit: Integer
    )
    .returns(T::Array[TeamBypassActor])
  end
  def self.suggest_bypassers(source, current_user, query, filter_repo_results: false, limit: 10)
    return [] if source.is_a?(Business)
    organization = nil
    repository = nil
    query = query&.downcase

    if source.is_a?(Organization)
      organization = source

      filter_repo_results = false
    elsif source.in_organization?
      organization = T.must(source.organization)
      repository = source

      filter_repo_results &&= repository.async_scoped_feature_flag_enabled?(:rule_pr_required_reviewers_filter_suggestions).sync
    else
      # Teams are not available without some connection to an Organization
      return []
    end

    if source.rules_more_efficient_teams_for?
      scope = organization.visible_teams_for(current_user).closed
      teams = Team.search_name_and_slug(query:, scope:)
    elsif filter_repo_results
      scope = repository.teams.closed
      teams = Team.search_name_and_slug(query:, scope:)
    else
      teams = []
      organization.visible_teams_for(current_user).each do |team_to_add|
        next if team_to_add.secret?
        if query.present?
          if team_to_add.name.downcase.start_with?(query)
            teams.unshift(team_to_add)
          elsif team_to_add.name.downcase.include?(query)
            teams.push(team_to_add)
          end
        else
          teams.push(team_to_add)
        end
      end
    end

    teams = teams.first(limit)
    bypass_actors = teams.map { |team| TeamBypassActor.new(actor: team) }
    bypass_actors
  end

  sig do
    params(
      bypassers: T::Array[TeamBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: RuleEngine::Conditions::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    allowed_modes = []

    user = actor.is_a?(User) ? actor : actor.owner
    return [] if user.nil?

    bypassers.group_by { |bypass| bypass.bypass_mode }.each do |mode, team_bypass|
      team_ids = team_bypass.map { |bypass| bypass.actor_id }
      allowed_modes << mode if Team.member_of?(team_ids, user.id, immediate_only: false)
    end
    allowed_modes
  end

  sig { params(repository: Repository, bypass_actors: T::Array[RepositoryRulesetBypassActor]).returns(T::Array[Integer]) }
  def self.bypassable_user_ids(repository, bypass_actors)
    team_ids = bypass_actors.map(&:actor_id)
    Team.member_ids_of(team_ids, immediate_only: false)
  end
end
