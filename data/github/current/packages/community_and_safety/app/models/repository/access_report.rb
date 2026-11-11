# typed: true
# frozen_string_literal: true

class Repository::AccessReport
  include Scientist

  FILENAME_SUFFIX = "-collaborators.csv"

  attr_reader :repository, :viewer

  # Public: Initialize a Repository::AccessReport.
  #
  # repository - The Repository the report is being generated for.
  # viewer     - The User requesting the report.
  def initialize(repository:, viewer:)
    @repository = repository
    @viewer     = viewer
  end

  # Public: Generate a CSV report of users with access to this repository.
  #
  # Returns a String.
  def generate_csv
    CSV.generate do |csv|
      # set the headers for the csv
      csv << %w[login permission]

      access_levels.each do |display_login, access|
        csv << [display_login, access]
      end
    end
  end

  # Public: The filename that is used for the CSV report.
  #
  # Returns a String.
  def filename
    "#{repository.name}#{FILENAME_SUFFIX}"
  end

  private

  # Private: Batch load the access or role level for all users with access to the repository
  #
  # Returns a Hash{User => Symbol}
  def access_levels
    return @access_levels if defined?(@access_levels)

    _, role_map = repository.batch_action_and_role_level_for(users_with_access)

    access_levels = {}

    users_with_access.each do |user|
      access_levels[user.display_login] = role_map[user.id]
    end

    @access_levels = access_levels
  end

  # Private: Load the users with access to this repository that are viewable
  #          by the viewer.
  #
  # Returns an ActiveRecord::Relation<User>.
  def users_with_access
    return @users_with_access if defined?(@users_with_access)

    user_ids = repository.direct_or_team_member_ids(
      viewer: viewer,
      immediate_only: false,
    )
    users = User.where(id: user_ids).filter_spam_for(viewer).sort

    @users_with_access = users
  end
end
