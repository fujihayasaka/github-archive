# typed: true
# frozen_string_literal: true

class Api::RepositoryHashAlgorithm < Api::App
  include ReceiveSchemaWithOpenApi

  # Get the hash algorithm for a repository.
  get "/repositories/:repository_id/hash-algorithm", operation_id: "repos/get-hash-algorithm" do
    @accepted_scopes = %w(repo)

    repo = find_repo!

    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:repo_hash_algorithm, repo, default: false)

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver(:repository_hash_algorithm_hash, repo)
  end
end
