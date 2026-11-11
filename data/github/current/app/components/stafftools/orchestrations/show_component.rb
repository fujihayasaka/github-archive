# typed: true
# frozen_string_literal: true

class Stafftools::Orchestrations::ShowComponent < ApplicationComponent
  attr_reader :orchestration

  def initialize(orchestration:)
    @orchestration = orchestration
  end

  private

  def entity_id_name
    case orchestration
    when BusinessOrchestration
      "Enterprise ID"
    when OrganizationOrchestration
      "Organization ID"
    when TeamOrchestration
      "Team ID"
    when RepositoryOrchestration, PullRequestOrchestration
      "Repository ID"
    end
  end

  def entity_id_value
    case orchestration
    when BusinessOrchestration
      orchestration.business_id
    when OrganizationOrchestration
      orchestration.organization_id
    when TeamOrchestration
      orchestration.team_id
    when RepositoryOrchestration, PullRequestOrchestration
      orchestration.repository_id
    end
  end

  def render_additional_business_id?
    orchestration.is_a?(OrganizationOrchestration) ||
    orchestration.is_a?(TeamOrchestration)
  end

  def list_organization_ids?
    orchestration.is_a?(BusinessOrchestration) ||
    orchestration.is_a?(OrganizationOrchestration) ||
    orchestration.is_a?(TeamOrchestration)
  end

  def list_team_ids?
    orchestration.is_a?(BusinessOrchestration) ||
    orchestration.is_a?(OrganizationOrchestration)
  end

  def list_user_ids?
    orchestration.is_a?(BusinessOrchestration) ||
    orchestration.is_a?(OrganizationOrchestration) ||
    orchestration.is_a?(TeamOrchestration)
  end

  def render_retry?
    orchestration.is_a?(RepositoryOrchestration) && orchestration.can_retry_failed_orchestration?
  end

  def retry_path
    if render_retry?
      repo = orchestration.repository
      stafftools_repository_repository_orchestration_retry_path(
        repo.owner,
        repo.name,
        orchestration.id
      )
    end
  end
end
