# typed: true
# frozen_string_literal: true

class Stafftools::Orchestrations::ListComponent < ApplicationComponent
  # The associated Business, Organization, Team, or BusinessTeam
  attr_reader :entity
  # The Orchestrations to list
  attr_reader :orchestrations
  attr_reader :retention_limit

  def initialize(entity:, orchestrations:, retention_limit: Orchestration::RETENTION_LIMIT)
    @entity = entity
    @orchestrations = orchestrations
    @retention_limit = retention_limit
  end

  private

  def entity_type_name
    case entity
    when Business
      "enterprise"
    when Organization
      "organization or its owning enterprise"
    when Team
      "team"
    when Repository
      "repository"
    end
  end

  def show_orchestration_path(orchestration)
    case entity
    when Business
      stafftools_enterprise_orchestration_path(entity, orchestration)
    when Organization
      stafftools_user_orchestration_path(entity, orchestration)
    when BusinessTeam
      stafftools_enterprise_team_orchestration_path(entity.business, entity.id, orchestration)
    when Team
      stafftools_user_team_orchestration_path(entity.organization, entity, orchestration)
    when Repository
      case orchestration
      when PullRequestOrchestration
        gh_stafftools_repository_pull_request_orchestration_path(orchestration)
      when RepositoryOrchestration
        gh_stafftools_repository_repository_orchestration_path(orchestration)
      end
    end
  end

  def abbreviated_orchestration_type(orchestration)
    case orchestration
    when BusinessOrchestration
      orchestration.type.gsub("BusinessOrchestration", "")
    when OrganizationOrchestration
      orchestration.type.gsub("OrganizationOrchestration", "")
    when TeamOrchestration
      orchestration.type.gsub("TeamOrchestration", "")
    when PullRequestOrchestration
      orchestration.type.demodulize.to_s
    when RepositoryOrchestration
      orchestration.type.gsub("RepositoryOrchestration", "")
    end
  end

  def retention_limit_for_display
    retention_limit.inspect
  end
end
