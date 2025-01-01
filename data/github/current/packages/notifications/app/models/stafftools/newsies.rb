# typed: true
# frozen_string_literal: true

class Stafftools::Newsies
  def self.users_watching_repository(repository)
    sql = Arel.sql(<<-SQL, list_id: repository.id)
      SELECT user_id
      FROM   notification_subscriptions
      WHERE  list_type = 'Repository'
      AND    list_id = :list_id
      AND    NOT ignored
    SQL

    ids = Newsies::ListSubscription.connection.select_values(sql).uniq
    User.where(id: ids)
  end

  def self.users_ignoring_repository(repository)
    sql = Arel.sql(<<-SQL, list_id: repository.id)
      SELECT user_id
      FROM   notification_subscriptions
      WHERE  list_type = 'Repository'
      AND    list_id = :list_id
      AND    ignored = 1
    SQL

    ids = Newsies::ListSubscription.connection.select_values(sql).uniq
    User.where(id: ids).order("login ASC")
  end

  def self.subscriptions_for_issue(issue)
    sql = Arel.sql(<<-SQL, **build_sql_params(issue))
      SELECT user_id, reason
      FROM   notification_thread_subscriptions
      WHERE  list_type = 'Repository'
      AND    list_id = :list_id
      AND    thread_key = :thread_key
      AND    ignored = 0
    SQL

    data = Newsies::ThreadSubscription.connection.select_rows(sql)

    reasons = data.index_by { |id, _reason| id }
    ids = reasons.keys
    users = User.where(id: ids).order("login ASC")
    users.map do |user|
      reason = reasons[user.id].last
      Stafftools::IssueSubscription.new(user, reason)
    end
  end

  def self.users_ignoring_issue(issue)
    sql = Arel.sql(<<-SQL, **build_sql_params(issue))
      SELECT user_id
      FROM   notification_thread_subscriptions
      WHERE  list_type = 'Repository'
      AND    list_id = :list_id
      AND    thread_key = :thread_key
      AND    ignored = 1
    SQL

    ids = Newsies::ThreadSubscription.connection.select_values(sql).uniq
    User.where(id: ids).order("login ASC")
  end

  def self.build_sql_params(issue_or_discussion)
    {
      list_id: issue_or_discussion.notifications_list.id,
      thread_key: Newsies::Thread.to_key(issue_or_discussion),
    }
  end
  private_class_method :build_sql_params

end
