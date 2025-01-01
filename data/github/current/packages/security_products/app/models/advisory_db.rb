# typed: true
# frozen_string_literal: true

module AdvisoryDB
  ADVISORIES_REPOSITORY_DEFAULT_BRANCH = "main"
  ADVISORIES_REPOSITORY_NWO = ENV["GITHUB_ADVISORIES_REPO"] || "github/advisory-database"

  def self.advisories_repository
    Repository.with_name_with_owner(ADVISORIES_REPOSITORY_NWO)
  end

  def self.advisory_title(advisory, length: 60)
    if advisory.summary.present?
      advisory.summary
    else
      advisory.description.truncate(length, separator: /[^[[:word:]]]/)
    end
  end

  def self.repo_file_path(advisory)
    month = advisory.published_at.month.to_s.rjust(2, "0")

    "advisories/#{advisory.unreviewed? ? "unreviewed" : "github-reviewed"}/#{advisory.published_at.year}/#{month}/#{advisory.ghsa_id}/#{advisory.ghsa_id}.json"
  end

  # Strict case-sensitive validation used for persistence
  def self.valid_ghsa_id_pattern
    /GHSA(?:-[23456789cfghjmpqrvwx]{4}){3}/
  end

  # Case insensitive validation used for user-input values
  def self.valid_ghsa_id_input_pattern
    /GHSA(?:-[23456789cfghjmpqrvwx]{4}){3}/i
  end

  def self.canonical_case_for_ghsa_id(ghsa_id)
    return ghsa_id unless ghsa_id =~ valid_ghsa_id_input_pattern

    ghsa_id.partition("-").tap do |ghsa_id_components|
      ghsa_id_components.first.upcase!
      ghsa_id_components.last.downcase!
    end.join
  end

  def self.collaborator?(repository:, user:)
    return false if user.nil?

    # Note: having a custom role assigned to a user does not necessarily mean
    # the user is allowed to perform the action associated with the role.
    # Case in point is having solely the resolve role for dependabot alerts
    # does not mean authzd will ALLOW because the user has to match the rules
    # defined by the policy. In that case one of the rules that could match
    # to ALLOW is to have the view role in addition to resolve. Having
    # resolve alone gets DENIED, while having view + resolve gets allowed.
    [
      :advisory_management_authorized_for?,
      :code_scanning_readable_by?,
      :code_scanning_writable_by?,
      :code_scanning_analyses_deletable_by?,
      :can_view_vulnerability_alerts?,
      :can_resolve_vulnerability_alerts?,
      :can_view_secret_scanning_alerts?,
    ].any? { |method| repository.send(method, user) } || repository.can_resolve_secret_scanning_alerts?(user, [])
  end
end
