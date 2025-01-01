# typed: true
# frozen_string_literal: true

# Public: The Set of GitHub-owned client applications that we know a given user
# has installed.
class ClientApplicationSet
  APPLICATIONS = {
    github_for_mac: 0,
    github_for_windows: 1,
    github_for_visual_studio: 2,
    github_desktop: 3,
    xcode: 4,
  }.freeze

  VALID_APPLICATIONS = APPLICATIONS.keys.freeze

  # Internal: Integer number of seconds to cache the fact that the user has a
  # particular application installed.
  CACHE_TTL = 30.days.to_i

  attr_reader :user_id

  # Public: Initialize a ClientApplicationSet for the given user.
  #
  # user_id - The Integer ID for the user.
  def initialize(user_id)
    @user_id = user_id

    if @user_id.blank?
      raise ArgumentError, "user_id cannot be blank"
    end
  end

  # Public: Adds the given application to the user's set of installed
  # applications.
  #
  # application - A Symbol identifying the application to add.
  #
  # Returns true if the application was added to the user's set of installed
  #   apps; or false if the application was already in the user's set of
  #   installed apps.
  def add(application)
    validate_application(application)

    return false unless GitHub.cache.add(cache_key(application), true, CACHE_TTL)

    return false if include?(application)

    application_id = APPLICATIONS[application]
    statement = <<-SQL
      INSERT IGNORE INTO client_application_sets (user_id, application_id, created_at)
      VALUES (:user_id, :application_id, NOW())
    SQL

    ActiveRecord::Base.connected_to(role: :writing) do
      affected_rows = ApplicationRecord::Domain::Users.connection.update(Arel.sql(statement, user_id: @user_id, application_id: application_id))
      affected_rows > 0
    end
  end

  # Public: Does the user have the given application installed?
  #
  # application - A Symbol identifying the application.
  #
  # Returns a Boolean.
  def include?(application)
    validate_application(application)

    application_id = APPLICATIONS[application]
    statement = <<-SQL
      SELECT 1 FROM client_application_sets
      WHERE user_id = :user_id AND application_id = :application_id
      LIMIT 1
    SQL
    value = ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(statement, user_id: @user_id, application_id: application_id))
    value.present?
  end

  # Public: Empties the user's set of installed applications.
  #
  # Returns nothing.
  def clear
    statement = <<-SQL
      DELETE FROM client_application_sets
      WHERE user_id = :user_id
    SQL
    ApplicationRecord::Domain::Users.connection.delete(Arel.sql(statement, user_id: user_id))
  end

  private

  def validate_application(application)
    unless VALID_APPLICATIONS.include?(application)
      raise ArgumentError, "application #{application} not a valid application (#{VALID_APPLICATIONS.to_sentence})"
    end
  end

  def cache_key(application)
    application_id = APPLICATIONS.fetch(application)
    "client_application_sets:#{user_id}:#{application_id}"
  end
end
