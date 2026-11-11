# typed: strict
# frozen_string_literal: true

# Encapsulates background job enqueueing for applying security configuration
# changes across organizations and enterprises.
module SecurityConfiguration::JobOrchestration
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SecurityConfiguration }

  # WARNING: Do not pass repositories when target is a Business (enterprise config).
  # The repositories parameter is only supported for Organization targets.
  sig do
    params(
      target: T.any(Business, Organization),
      actor: User,
      repositories: T.nilable(SecurityProductsEnablement::RepositorySelection),
      policy: T.nilable(SecurityConfigurationPolicy),
    ).void
  end
  def enqueue_configuration_jobs(target:, actor:, repositories: nil, policy: nil)
    return unless any_feature_previously_changed? || policy&.enforcement_previously_changed? || repositories

    options = secret_scanning_scan_triggering_feature_is_enabled? ? { publish_backfill_group_request: true } : {}

    case target
    when Business
      enqueue_enterprise_update_job(target:, actor:, options:)
    when Organization
      if repositories
        enqueue_organization_update_and_replace_repositories_job(target:, actor:, repositories:, options:)
      else
        enqueue_organization_update_job(target:, actor:, options:)
      end
    end
  end

  private

  sig { params(target: Business, actor: User, options: T::Hash[Symbol, T.untyped]).void }
  def enqueue_enterprise_update_job(target:, actor:, options:)
    SecurityProductsEnablement::EnterpriseSecurityConfigurationJob.perform_later(
      security_configuration_id: id,
      enterprise_id: target.id,
      actor_id: actor.id,
      action: :update,
      options:
    )
  end

  sig { params(target: Organization, actor: User, options: T::Hash[Symbol, T.untyped]).void }
  def enqueue_organization_update_job(target:, actor:, options:)
    SecurityProductsEnablement.domain.configurations.enqueue_bulk_attachment(
      security_configuration_id: id,
      organization: target,
      actor_id: actor.id,
      action: :update,
      options:,
    )
  end

  sig do
    params(
      target: Organization,
      actor: User,
      repositories: SecurityProductsEnablement::RepositorySelection,
      options: T::Hash[Symbol, T.untyped],
    ).void
  end
  def enqueue_organization_update_and_replace_repositories_job(target:, actor:, repositories:, options:)
    SecurityProductsEnablement.domain.configurations.enqueue_bulk_attachment(
      security_configuration_id: id,
      organization: target,
      actor_id: actor.id,
      action: :update_and_replace_repositories,
      repositories:,
      options:,
    )
  end
end
