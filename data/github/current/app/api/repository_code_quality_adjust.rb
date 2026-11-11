# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeQualityAdjust < Api::App
  include Api::App::CodeScanningHelpers
  include Api::App::CodeQualityHelpers

  patch "/repositories/:repository_id/code-quality/adjust", operation_id: "code-quality/adjust", read_from_replicas: true do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    ensure_read_access_and_code_quality_enabled!(repo, forbid: repo.public?)

    if FeatureFlag.vexi.enabled?(:use_code_quality_fgr, repo, default: false)
      control_access :write_code_quality,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        forbid: true,
        forbid_message: "You are not authorized to adjust Code quality managed analysis configuration."
    else
      control_access :write_code_scanning,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        forbid: true,
        forbid_message: "You are not authorized to adjust Code quality managed analysis configuration."
    end

    deliver_error_if_archived!(repo)

    data = receive_with_openapi

    adjust_managed_analyses_configuration!(repo, data, :CODE_QUALITY)
  end
end
