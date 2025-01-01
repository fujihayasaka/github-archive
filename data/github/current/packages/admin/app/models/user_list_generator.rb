# typed: true
# frozen_string_literal: true

# This is the runner for the ghe-user-csv command, by way of script/ghe-user-csv.

class UserListGenerator
  include Scientist

  class Error < StandardError
  end

  attr_reader :restrict_type

  # Create a new user list generator.
  def initialize(restrict_type: nil)
    raise Error, "User list generation only works in enterprise" unless GitHub.enterprise?
    @restrict_type = restrict_type
  end

  # Returns an Array of user account information. What user information is
  # returned is decided by the query in user_query and complete_results
  def run
    query = user_query

    case restrict_type
    when :admins
      query += Arel.sql "\nAND users.gh_role = 'staff'"
    when :users
      query += Arel.sql "\nAND users.gh_role IS NULL"
    when :suspended
      query += Arel.sql "\nAND users.suspended_at IS NOT NULL "
    end

    query += Arel.sql "\nORDER BY users.login"

    rows = User.connection.select_rows(query)
    if restrict_type == :builtin
      rows.reject! { |row| GitHub.auth.external_user?(row[1]) }
    end
    complete_results(rows)
  end

  protected

  # Query used for fetching user accounts, can be overridden in a subclass
  def user_query
    Arel.sql <<-SQL
      SELECT
        users.id,
        users.login,
        (SELECT IFNULL(ue.email, 'N/A')
         FROM user_emails ue
         JOIN email_roles er ON ue.id = er.email_id
         WHERE ue.user_id = users.id AND er.role = 'primary') as email,
        users.created_at as creation_date
      FROM users
      WHERE users.type = 'User'
      AND users.login <> 'ghost'
    SQL
  end

  # Completes the query results by adding to each row, the count of different
  # organizations the user belongs to. Can be overridden in a subclass
  def complete_results(results)
    results.map do |row|
      user_id, login, email, creation_date = *row
      { id: user_id, login: login, email: email, creation_date: creation_date.to_formatted_s(:db) }
    end
  end

  private

  # Returns a hash where the keys are user ids and values are the number of
  # different orgs the user belongs to.
  def users_org_counts(user_ids)
    users_teams = users_teams(user_ids)
    team_ids = users_teams.values.flatten.uniq
    teams_orgs = teams_orgs(team_ids)

    result = {}

    users_teams.each do |user, teams|
      result[user] = teams.map { |team_id| teams_orgs[team_id] }.compact.uniq.length
    end

    result
  end

  # Returns a hash where the keys are user ids and values arrays containing
  # the ids of the teams that users belong to.
  def users_teams(user_ids)
    Platform::Loaders::UserTeams.new.fetch(user_ids)
  end

  # Returns a hash where each key is the id of a team and each value
  # is the id of the org that team belong to.
  def teams_orgs(team_ids)
    result = {}

    Team.where(id: team_ids).select("id, organization_id").find_each do |team|
      result[team.id] = team.organization_id
    end

    result
  end

  def show_header?
    @show_header
  end
end
