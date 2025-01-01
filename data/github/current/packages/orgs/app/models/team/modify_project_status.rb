# typed: true
# frozen_string_literal: true

# Public: A response is created when a project is added to a team, or permissions updated
class Team::ModifyProjectStatus
  # Internal: Successful statuses.
  SUCCESSFUL = [:success]

  # Public: A Symbol.
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

  # Public: The project is not owned by an organization.
  NON_ORGANIZATION_PROJECT = new(:non_org_project)

  # Public: Team already has access to project.
  DUPE = new(:dupe)

  # Public: The team's org and the project's org aren't the same.
  NOT_OWNED = new(:not_owned)

  # Public: Permission to give to project was not specified.
  NO_PERMISSION = new(:no_permission)

  UNKNOWN_ERROR = new(:unknown_error)

  # Public: It's all good.
  SUCCESS = new(:success)
end
