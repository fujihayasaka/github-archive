# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningCodeqlAction < Api::App
  include Api::App::CodeScanningHelpers

  # The maximum number of features that can be requested.
  MAX_FEATURES = 25

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/repositories/:repository_id/code-scanning/codeql-action/features", operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/code-scanning-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :read_code_scanning,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    requested_features = nil

    if params.has_key?("features")
      requested_features = params["features"].split(",").map(&:strip)

      if requested_features.length > MAX_FEATURES
        deliver_error! 400, message: "Can request a maximum of #{MAX_FEATURES} features."
      end
    end

    deliver(:raw, GitHub::CodeQLAction.feature_flags_for(repo, requested_features), status: 200)
  end
end
