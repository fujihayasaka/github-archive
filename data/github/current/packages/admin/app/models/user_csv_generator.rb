# typed: true
# frozen_string_literal: true

require "github/enterprise_accounts/kv"

# This is the runner for the ghe-user-csv command, by way of script/ghe-user-csv.

class UserCSVGenerator < UserListGenerator
  include Scientist
  HEADER = "login,email,role,ssh_keys,org_memberships,repos,suspension_status,large_scale_contributor,last_logged_ip,creation_date".freeze

  # Create a new CSV generator.
  #
  # output_io:     - An open IO handle to print the CSV results to. Usually
  #                  either a file in /tmp, or STDOUT.
  # show_header:   - Whether or not to include the CSV header in the output.
  #                  Default is false.
  # restrict_type: - What kind of record to output. Can be nil (all records),
  #                  :admins to print out just site admins, :users for normal
  #                  non-admin users, and :suspended to include suspended users.
  #                  Default is nil.
  def initialize(output_io:, show_header: false, restrict_type: nil)
    super(restrict_type: restrict_type)
    @output        = output_io
    @show_header   = show_header
  end

  # Prints a CSV in @output, where each row cotains the following information:
  #
  #  * login
  #  * email
  #  * role
  #  * ssh_keys (count)
  #  * org_memberships (count)
  #  * repos (count)
  #  * suspension_status
  #  * last_logged_ip
  #  * creation_date
  #
  def run
    rows = super

    if show_header?
      @output.puts HEADER
    end

    @output.puts rows.join("\n")
  end

  private

  # Overrides the user query to return
  #
  #  * login
  #  * email
  #  * role
  #  * ssh_keys (count)
  #  * org_memberships (count)
  #  * repos (count)
  #  * suspension_status
  #  * last_logged_ip
  #  * creation_date
  def user_query
    Arel.sql <<-SQL
      SELECT
        users.id,
        users.login,
        (SELECT IFNULL(ue.email, 'N/A')
         FROM user_emails ue
         JOIN email_roles er ON ue.id = er.email_id
         WHERE ue.user_id = users.id AND er.role = 'primary') as email,
         IF(users.gh_role='staff', 'admin', 'user') as role,
         (SELECT COUNT(*) FROM public_keys WHERE public_keys.user_id = users.id) as ssh_keys,
        IF(users.suspended_at IS NULL, 'active', 'suspended') as suspension_status,
        IFNULL(users.last_ip, 'N/A') as last_logged_ip,
        users.created_at as creation_date
      FROM users
      WHERE users.type = 'User'
      AND users.login <> 'ghost'
    SQL
  end

  # Completes the query results by adding to each row, the count of different
  # organizations the user belongs to.
  def complete_results(results)
    user_ids          = results.map(&:first)
    users_org_counts  = users_org_counts(user_ids)
    user_repo_counts  = user_repo_counts(user_ids)

    results.map do |(user_id, login, email, role, ssh_keys, suspension_status, last_logged_ip, creation_date)|
      [login, email, role, ssh_keys, users_org_counts[user_id], user_repo_counts[user_id],
       suspension_status, large_scale_contributor?(user_id), last_logged_ip, creation_date.to_formatted_s(:db)].join(",")
    end
  end

  def user_repo_counts(user_ids)
    Repository.where(owner_id: user_ids).group(:owner_id).count.tap { |hash| hash.default = 0 }
  end

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

  def large_scale_contributor?(user_id)
    EnterpriseAccounts::KV.store.exists("user.large_scale_contributor.#{user_id}").value { false }
  end

  def show_header?
    @show_header
  end
end
