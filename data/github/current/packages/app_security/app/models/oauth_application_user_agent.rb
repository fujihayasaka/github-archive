# typed: true
# frozen_string_literal: true

class OauthApplicationUserAgent
  # Each app has a id, name, ua_regex, patched_version The id is used to
  # identify the unique app in this hash for checking the action restraint
  # before notifying the user. It has no correlation with the oauth app ID.
  # The regex uses 3 capture groups to find the major.minor.patch version for
  # the given app lastly the name and patched_version are the human readable
  # informational bits sent to the user via email
  APP_UPGRADE_AVAILABLE_USER_AGENTS = [
    {
      id: 1,
      name: "GitHub Desktop",
      ua_regex: /GitHubDesktop\/([0-9]+.[0-9]+.[0-9]+)/,
      patched_version: "2.5.3",
      current_sessions_affected: false,
    }.freeze,
    {
      id: 2,
      name: "Git Credential Manager",
      ua_regex: /git-credential-manager.*git-tools\/([0-9]+.[0-9]+.[0-9]+)/,
      patched_version: "2.29",
      current_sessions_affected: false,
    }
  ].freeze

  attr_reader :id, :name, :current_version, :patched_version, :current_sessions_affected

  def initialize(id:, name:, current_version:, patched_version:, current_sessions_affected:)
    @id = id
    @name = name
    @current_version = current_version
    @patched_version = patched_version
    @current_sessions_affected = current_sessions_affected
  end

  def outdated?
    Gem::Version.new(self.current_version) < Gem::Version.new(self.patched_version)
  end

  def git_credential_manager?
    self.id == 2
  end

  def self.from_user_agent(user_agent)
    return nil if user_agent.blank?

    APP_UPGRADE_AVAILABLE_USER_AGENTS.each do |app|
      if found = user_agent.match(app[:ua_regex])
        return self.new(
          **app.slice(:id, :name, :patched_version, :current_sessions_affected),
          current_version: found.captures.first.strip,
        )
      end
    end

    nil
  end

  def self.from_app_id_and_current_version(app_id:, current_version:)
    app = APP_UPGRADE_AVAILABLE_USER_AGENTS.find { |app| app[:id] == app_id }
    self.new(
      **app.slice(:id, :name, :patched_version, :current_sessions_affected),
      current_version: current_version,
    )
  end
end
