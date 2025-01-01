# typed: true
# frozen_string_literal: true

# Public: A response is created when a repo is added to a team, or permissions updated
class Team::ModifyRepositoryStatus

  # Internal: Successful statuses.
  SUCCESSFUL = [:dupe, :owners, :success]

  # Public: A Symbol. :success, :blocked, :dupe, or :org.
  attr_reader :status

  def initialize(status)
    @status = status
    freeze
  end

  private :initialize

  # Public: Did an error occur while adding a member?
  def error?
    !success?
  end

  # Public: Was a member successfully added?
  def success?
    SUCCESSFUL.include?(status)
  end

  def message
    case @status
    when DUPE.status
      "Team already has access to the repository."
    when NOT_OWNED.status
      "The team's organization and the repository's organization aren't the same."
    when ADVISORY_WORKSPACE.status
      "Access to temporary private forks must be managed through their advisories."
    when GROUP_SETTINGS.status
      "Access to repository is managed by Group Settings"
    when NO_PERMISSION.status
      "Permission to give to the repository was not specified."
    when OWNERS.status
      "The Owners team has implicit access to all organization repositories."
    when NO_DIRECT_ORG.status
      "Direct organization membership is not enabled."
    when REPOSITORY_LOCKED.status
      "This repository is locked and cannot be modified."
    else
      msg = success? ? "Repository was successfully added to the team." : "Repository was not added to the team."
      "#{msg} Reason: #{@status}."
    end
  end

  # Public: Team already has access to repo.
  DUPE = new(:dupe)

  # Public: The team's org and the repo's org aren't the same.
  NOT_OWNED = new(:not_owned)

  ADVISORY_WORKSPACE = new(:advisory_workspace)

  # Public: Permission to give to repo was not specified.
  NO_PERMISSION = new(:no_permission)

  # Public: The Owners team has implicit access to all org repos.
  OWNERS = new(:owners)

  # Public: It's all good.
  SUCCESS = new(:success)

  # Direct Org Membership is not enabled
  NO_DIRECT_ORG = new(:no_direct_org)

  # Public: The repository is currently locked and cannot be modified.
  REPOSITORY_LOCKED = new(:repository_locked)

  # Public: Access to repository is managed by Group Settings
  GROUP_SETTINGS = new(:group_settings)
end
