# typed: true
# frozen_string_literal: true

module Stafftools
  class Team < SimpleDelegator
    def self.for_organization(org, query: nil, page: 1)
      teams = org.teams
      query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
      if query.present?
        teams = teams.where(["name LIKE :query OR slug LIKE :query", { query: "%#{query}%" }])
      end
      teams = teams.paginate(page: page)
      return ::Team.none unless teams.present?

      team_members = teams_with_members(teams)
      team_counts = team_member_counts(teams, team_members)

      async_decorated_teams = teams.map do |team|
        Promise.all([
          team.async_externally_managed?,
          team.async_pending_team_membership_requests,
          team.async_group_mappings,
        ]).then do |is_externally_managed, pending_team_membership_requests, group_mappings|
          {
            team: team,
            num_members: team_counts[team.id].length,
            externally_managed: is_externally_managed,
            pending_team_membership_requests: pending_team_membership_requests,
            group_mappings: group_mappings
          }
        end
      end

      remapped_teams = Promise.all(async_decorated_teams).sync.map do |hsh|
        new(hsh[:team], hsh[:num_members], hsh)
      end

      Stafftools::PaginatedCollection.create(teams, remapped_teams)
    end

    def self.teams_with_members(teams)
      sql_bindings = {
        direct: Ability.priorities[:direct],
        subject_id: teams.map(&:ability_id),
        subject_type: teams.first.ability_type,
      }

      sql = Arel.sql <<-SQL, **sql_bindings
          SELECT subject_id, actor_id
          FROM   abilities
          WHERE  actor_type   = "User"
          AND    subject_id   IN (:subject_id)
          AND    subject_type = :subject_type
          AND    priority     <= :direct
      SQL

      Ability.connection.select_rows(sql)
    end

    def self.team_member_counts(teams, team_members)
      results = Hash.new { |hash, key| hash[key] = Set.new }
      team_members.each { |team_id, user_id| results[team_id] << user_id }

      results
    end

    attr_reader :num_members,
                :pending_team_membership_requests,
                :externally_managed

    alias_method :externally_managed?, :externally_managed

    def initialize(team, num_members, opts = {})
      @num_members = num_members
      @externally_managed = opts.fetch(:externally_managed, false)
      @pending_team_membership_requests = opts.fetch(:pending_team_membership_requests, [])
      @group_mappings = opts.fetch(:group_mappings, [])
      super team
    end

    def mapping_sync_status
      @group_mappings.first&.status
    end

    def mapping_sync_status_label
      mapping_sync_status == "failed" ? :orange : :secondary
    end

    def enterprise_team_managed?
      # Call the original method on the Team model
      __getobj__.enterprise_team_managed?
    end
  end
end
