# typed: strict
# frozen_string_literal: true

class Api::Internal::UIManifests < Api::Internal
  post "/internal/ui_manifests/update", operation_id: :internal do
    @route_owner = T.let("@github/frontend-systems", T.nilable(String))

    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    data = receive(Hash, required: true)
    target = data["target"]
    git_sha = data["gitSha"]
    manifest = data["manifest"]

    if !target
      return deliver_error(400, message: "Missing target")
    end

    if !git_sha
      return deliver_error(400, message: "Missing Git SHA")
    end

    if !manifest
      return deliver_error(400, message: "Missing manifest")
    end

    GitHubUI::ManifestStore.set(target: target, git_sha: git_sha, manifest: manifest)

    deliver_empty(status: 200)
  end

  sig { returns(T::Boolean) }
  def require_request_hmac?
    # HMAC keys are stored in "GitHub.api_internal_ui_manifests_hmac_keys"
    # which reads "API_INTERNAL_UI_MANIFESTS_HMAC_KEYS" environment variable
    true
  end

  sig { returns(T::Boolean) }
  def externally_accessible?
    # This API should not be accessible from outside the GitHub network
    # to prevent UI deploys outside of heaven
    false
  end
end
