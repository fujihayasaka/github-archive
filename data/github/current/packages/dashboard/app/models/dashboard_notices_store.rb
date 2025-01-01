# typed: true
# frozen_string_literal: true
require "github/result"

class DashboardNoticesStore

  UnavailableError = Class.new(StandardError)

  # Public: Get all the active DashboardNotices for this user.
  # Limited to 100 notices
  #
  # user_id - The Integer User ID.
  #
  # Examples
  #
  #   DashboardNoticesStore.get_for_user_id(123)
  #   # => #<GitHub::Result value: [#<DashboardNotice name: "orgs_newbie">]>
  #
  # Returns a GitHub::Result. When successful, the Result's value is an Array
  # of DashboardNotice.
  def self.get_for_user_id(user_id)
    statement = <<-SQL
      SELECT notice_name FROM dashboard_notices
      WHERE user_id = :user_id AND active = 1
      LIMIT 100
    SQL

    GitHub::Result.new do
      encapsulate_error do
        ApplicationRecord::Domain::Users.connection.select_rows(Arel.sql(statement, user_id: user_id))
                   .flatten
                   .map { |item| DashboardNotice.new(item) }
      end
    end
  end

  # Public: Add a new DashboardNotice for a given user
  #
  # user_id - The Integer User ID.
  # notice_name - A string representing the name of the notice to add
  #
  # Examples
  #
  #   DashboardNoticesStore.add(123, "orgs_newbie")
  #   # => #<GitHub::Result value: true>
  #
  #   DashboardNoticesStore.add(123, "orgs_newbie")
  #   # => #<GitHub::Result value: false>
  #   # when the corresponding notice was not added
  #
  # Returns a GitHub::Result with the value of true, when the notice was added,
  # and false otherwise.
  def self.add(user_id, notice_name)
    statement = <<-SQL
      INSERT IGNORE INTO dashboard_notices (user_id, notice_name, active, created_at, updated_at)
      VALUES (:user_id, :notice_name, :active, NOW(), NOW())
    SQL

    GitHub::Result.new do
      encapsulate_error do
        affected_rows = ApplicationRecord::Domain::Users.connection.update(Arel.sql(statement, user_id: user_id, notice_name: notice_name, active: 1))
        affected_rows == 1
      end
    end
  end

  def self.bulk_add(user_ids, notice_name)
    data_rows = user_ids.map do |id|
      [
        id,                # user_id
        notice_name.to_s,  # notice_name
        1,                 # active
        Time.now.iso8601,  # created_at
        Time.now.iso8601,  # updated_at
      ]
    end

    statement = Arel.sql <<-SQL
      INSERT IGNORE INTO dashboard_notices (user_id, notice_name, active, created_at, updated_at) :rows
    SQL

    GitHub::Result.new do
      encapsulate_error do
        affected_rows = ApplicationRecord::Domain::Users.connection.update(Arel.sql(statement, rows: Arel::Nodes::ValuesList.new(data_rows)))
        affected_rows == user_ids.size
      end
    end
  end

  # Public: Deletes a notice by user id and notice name
  #
  # user_id - The Integer User ID.
  # notice_name - A string representing the name of the notice to delete
  #
  # Example:
  #
  #   DashboardNoticesStore.delete(123, "orgs_newbie")
  #   # => #<GitHub::Result value: true>
  #
  #   DashboardNoticesStore.delete(123, "orgs_newbie")
  #   # => #<GitHub::Result value: false>
  #
  # Returns a Result with the value of true, when the notice was deleted,
  # and false otherwise.
  def self.delete(user_id, notice_name)
    statement = <<-SQL
      DELETE FROM dashboard_notices
      WHERE user_id = :user_id AND notice_name = :notice_name
    SQL

    GitHub::Result.new do
      encapsulate_error do
        affected_rows = ApplicationRecord::Domain::Users.connection.delete(Arel.sql(statement, user_id: user_id, notice_name: notice_name))
        affected_rows == 1
      end
    end
  end

  # Public: Deletes notices by user ID.
  #
  # user_id - The Integer User ID.
  #
  # Example:
  #
  #   DashboardNoticesStore.delete(123)
  #   # => #<GitHub::Result value: true>
  #
  #   DashboardNoticesStore.delete(123)
  #   # => #<GitHub::Result value: false>
  #
  # Returns a GitHub::Result with the value of true if any notices were deleted,
  # and false otherwise.
  def self.delete_all_for_user(user_id)
    statement = <<-SQL
      DELETE FROM dashboard_notices
      WHERE user_id = :user_id
    SQL

    GitHub::Result.new do
      encapsulate_error do
        affected_rows = ApplicationRecord::Domain::Users.connection.delete(Arel.sql(statement, user_id: user_id))
        affected_rows > 0
      end
    end
  end

  # Public: Deactivates a notice by user id and notice name
  #
  # user_id - The Integer User ID.
  # notice_name - A string representing the name of the notice to deactivate
  #
  # Example:
  #
  #   DashboardNoticesStore.deactivate(123, "orgs_newbie")
  #   # => #<GitHub::Result value: true>
  #
  #   DashboardNoticesStore.deactivate(123, "orgs_newbie")
  #   # => #<GitHub::Result value: false>
  #
  # Returns a GitHub::Result with the value of true, when the notice was
  # deactivated, and false otherwise.
  def self.deactivate(user_id, notice_name)
    statement = <<-SQL
      UPDATE dashboard_notices
      SET active = :active, updated_at = NOW()
      WHERE user_id = :user_id AND notice_name = :notice_name
    SQL

    GitHub::Result.new do
      encapsulate_error do
        affected_rows = ApplicationRecord::Domain::Users.connection.update(Arel.sql(statement, user_id: user_id, notice_name: notice_name, active: 0))
        affected_rows == 1
      end
    end
  end

  def self.encapsulate_error(&block)
    yield
  rescue SystemCallError, ActiveRecord::NoDatabaseError => e
    raise UnavailableError, "#{e.class}"
  end
  private_class_method :encapsulate_error
end
