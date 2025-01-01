# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecretScanning::AbstractController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include Orgs::SecurityCenter::SecretScanningOrgQueriesHelper

  private

  sig { void }
  def feature_required
    render_404 unless SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(this_organization)
  end

  sig { returns(T::Boolean) }
  def has_repositories?
    allowed_repo_ids, _ = allowed_repository_ids_for_organization_members
    return false unless allowed_repo_ids
    allowed_repo_ids.size > 0
  end

  sig { returns(SecretScanning::AlertQueryService) }
  def alert_query_service
    allowed_repository_ids, _ = allowed_repository_ids_for_organization_members
    build_alert_query_service(allowed_repository_ids: allowed_repository_ids)
  end

  sig { returns(SecretScanning::AlertQueryService) }
  def alert_query_service_with_repositories_from_params
    allowed_repository_ids = repository_ids_from_params_for_secret_scanning

    if allowed_repository_ids.nil?
      allowed_repository_ids, _ = allowed_repository_ids_for_organization_members
    end

    build_alert_query_service(allowed_repository_ids: allowed_repository_ids)
  end

  sig { returns(T.nilable([T::Array[Integer], T::Boolean])) }
  def allowed_repository_ids_for_organization_members
    allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::SECRET_SCANNING]
  end

  sig { returns(Search::Queries::SecurityCenter::SecretScanningQuery) }
  def parsed_query
    alert_query_service.parsed_query
  end

  sig { params(allowed_repository_ids: T.nilable(T::Array[Integer])).returns(SecretScanning::AlertQueryService) }
  def build_alert_query_service(allowed_repository_ids:)
    kwargs = {
      organization: this_organization,
      query: params[:query],
      current_user:,
      user_session:,
      allowed_repository_ids:
    }
    SecretScanning::AlertQueryService.for_organization(**kwargs)
  end
end
