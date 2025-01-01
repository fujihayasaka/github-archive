# typed: true
# frozen_string_literal: true

class Api::RepositoryKeys < Api::App
  include ReceiveSchemaWithOpenApi
  include PublicKeyHelpers

  # List deploy keys for a repo
  get "/repositories/:repository_id/keys", operation_id: "repos/list-deploy-keys" do
    control_access :list_repo_keys,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    keys = repo.public_keys.includes([:repository, :user, :creator])
    keys = paginate_rel(keys)

    deliver :public_key_hash, keys
  end

  # Get a deploy key
  get "/repositories/:repository_id/keys/:key_id", operation_id: "repos/get-deploy-key" do
    key, repo = find_repo_and_key!
    control_access :get_repo_key,
      resource: repo,
      key: key,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    deliver :public_key_hash, key, last_modified: calc_last_modified_for_object(key)
  end

  # Create a deploy key
  post "/repositories/:repository_id/keys", operation_id: "repos/create-deploy-key" do
    control_access :add_repo_key, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true

    return deliver_user_agent_blocked_error! if user_agent_blocked_from_adding_pubkey? user_agent.string

    # Introducing strict validation of the deploy-key.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("deploy-key", "create", skip_validation: true)
    read_only = data["read_only"] == true

    options = {
      title: data["title"],
      key: data["key"],
      read_only: read_only,
      oauth_authorization: current_user.oauth_access&.authorization,
      verifier: current_user,
    }

    public_key = repo.public_keys.create_with_verification(options)

    if !public_key.new_record?
      deliver :public_key_hash, public_key, status: 201
    else
      deliver_error! 422,
        errors: public_key.errors,
        documentation_url: @documentation_url
    end
  end

  # Delete a deploy key
  delete "/repositories/:repository_id/keys/:key_id", operation_id: "repos/delete-deploy-key" do
    # Introducing strict validation of the deploy-key.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("deploy-key", "delete", skip_validation: true)

    key, repo = find_repo_and_key!
    control_access :manage_repo_key, resource: repo, key: key, allow_integrations: true, allow_user_via_granular_actor: true
    key.destroy_with_explanation(:removed_by_user)
    deliver_empty(status: 204)
  end

  private

  def find_repo_and_key!
    repo = find_repo!
    key  = PublicKey.find_by(repository_id: repo.id, id: int_id_param!(key: :key_id))

    record_or_404(key)

    [key, repo]
  end
end
