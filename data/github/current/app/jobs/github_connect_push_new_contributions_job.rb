# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitHubConnectPushNewContributionsJob < ApplicationJob
  queue_as :github_connect

  schedule interval: 10.minutes, condition: -> { GitHub.enterprise? }

  # Perform a contributions push to DotCom for the earliest contributions made and limit them by 100.
  # Update the last_contributions_sync for the users whose contributions have been pushed
  #
  def perform
    return unless GitHub.dotcom_contributions_enabled?
    Failbot.push(github_connect_push_new_contributions: true)

    pushable_users_batch.each_slice(100) do |slice|
      slice.each do |result|
        user = User.find(result.first)
        contributions = index_contributions_by_date(user, result.last)
        user_token = DotcomUser.for(user).token

        begin
          GitHub::Connect.post_contribution_data(user_token, user.login, contributions)
          with_write { DotcomUser.update_user_last_contributions_sync(user) }
        rescue GitHub::Connect::ApiError
          # Do nothing. This is logged by #post_contribution_data,
          # verifiable by the user on the profile connection admin,
          # and we want the other users to be processed.
        end
      end
    end
  end

  private

  # Query to return the count of dotcom_users who have enabled the feature
  #
  # last_contributions_sync is nil when the feature is disabled
  def enabled_users_count
    query = Arel.sql(<<-SQL)
      SELECT COUNT(*) FROM dotcom_users WHERE last_contributions_sync IS NOT NULL
    SQL

    DotcomUser.connection.select_values(query).first
  end

  # Query to return dotcom users that have not had their contributions pushed within the last hour
  # and limits them by the users_count
  # users_count: a sixth of the dotcom_users who have enabled the feature
  #
  # Returns an array of users who have not pushed their contributions for the longest time
  def pushable_users_batch
    users_count = (enabled_users_count / 6.0).ceil

    query = Arel.sql(<<-SQL, users_count: Arel.sql(users_count.to_s))
      SELECT user_id, last_contributions_sync FROM dotcom_users
      WHERE last_contributions_sync < NOW() - INTERVAL 1 HOUR
      ORDER BY last_contributions_sync ASC LIMIT :users_count
    SQL

    DotcomUser.connection.select_rows(query)
  end

  # Takes a user and the last_contributions_sync and gets the user's contributions
  # within the day before last_contributions_sync and now
  # It the indexes them by date with a contribution count for that date:
  #
  # [{"date" => 2018-04-24T00:00:00Z, "count" => 3}, {"date" => 2018-04-25T00:00:00Z, "count" => 7}, ..]
  #
  # Returns an Array of Hashes.
  def index_contributions_by_date(user, last_contributions_sync)
    yesterday = (last_contributions_sync.to_date - 1).to_time
    contributions_collector = Contribution::Collector.new(user: user, time_range: (yesterday)..(Time.zone.now))

    contributions_collector.contribution_count_by_day.map do |date, count|
      { "date" => date.to_time.utc.iso8601, "count" => count }
    end
  end
end
