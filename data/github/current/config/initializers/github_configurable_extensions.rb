# typed: true
# frozen_string_literal: true

require "configurable"

# This adds the Configurable bits needed for global settings such
# as disabling Organization creation and git SSH access.
module GitHub
  extend Configurable

  # Make GitHub quack a little like an AR object with an association.
  # The `reload` param is because has_many associations let you explicitly reload.
  # Don't remove it.
  def self.configuration_entries(reload = nil)
    Configuration::Entry.global
  end

  def self.configuration_entry_id
    0
  end

  def self.configuration_entry_type
    "global"
  end

  extend Configurable::GitLfs
  extend Configurable::OrgCreation
  extend Configurable::OrgMembershipVisibility
  extend Configurable::Ssh
  extend Configurable::SuggestedProtocol
  extend Configurable::ForcePushRejection
  extend Configurable::MaxObjectSize
  extend Configurable::DiskQuota
  extend Configurable::PackageRegistry
  extend Configurable::DefaultRepoVisibility
  extend Configurable::Showcase
  extend Configurable::CrossRepoConflictEditor
  extend Configurable::EnterpriseDormancyThreshold
  extend Configurable::AnonymousGitAccess
  extend Configurable::AnonymousGitAccessLock
  extend Configurable::DotcomSearch
  extend Configurable::DotcomPrivateSearch
  extend Configurable::DotcomContributions
  extend Configurable::DotcomUserLicenseUsageUpload
  extend Configurable::DotcomDownloadActionsArchive
  extend Configurable::GheContentAnalysis
  extend Configurable::GheDependabotAccessToDotcom
  extend Configurable::GheUsageMetrics
  extend Configurable::EnableProjectsAutomation
  extend Configurable::BusinessTeamsPerBusinessLimit
  extend Configurable::BusinessTeamMemberLimit
  extend Configurable::BusinessTeamOrganizationAssignmentLimit
end
