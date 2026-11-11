# typed: true
# frozen_string_literal: true

class Api::RepositoryAutolinks < Api::App
  include ReceiveSchemaWithOpenApi

  # Get all autolinks of a repo
  get "/repositories/:repository_id/autolinks", operation_id: "repos/list-autolinks" do
    repo = find_repo!
    control_access :list_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true

    autolinks = Repositories.domain.key_links.list_for_repo(repo.id)
    deliver :autolink_hash, autolinks
  end

  # Get a single autolink by ID
  get "/repositories/:repository_id/autolinks/:autolink_id", operation_id: "repos/get-autolink" do
    repo = find_repo!
    control_access :read_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    autolink = Repositories.domain.key_links.by_id(int_id_param!(key: :autolink_id), repo_id: repo.id)
    deliver :autolink_hash, autolink
  end

  # Create a new autolink
  post "/repositories/:repository_id/autolinks", operation_id: "repos/create-autolink" do
    repo = find_repo!
    control_access :create_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    data = receive_with_openapi

    attributes = Repositories::CreateKeyLinkAttributes.new(
      key_prefix: data["key_prefix"],
      url_template: data["url_template"]
    )

    attributes.is_alphanumeric = data["is_alphanumeric"] unless data["is_alphanumeric"].nil?

    result = Repositories.domain.key_links.create(attributes, repo_id: repo.id)
    case result
    when GH::Result::Ok
      deliver :autolink_hash, result.value, status: 201
    when GH::Result::Error::Validation
      deliver_error 422, errors: result.model.errors, documentation_url: @documentation_url
    end
  end

  # Delete an autolink
  delete "/repositories/:repository_id/autolinks/:autolink_id", operation_id: "repos/delete-autolink" do
    repo = find_repo!
    control_access :delete_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true

    result = Repositories.domain.key_links.destroy(int_id_param!(key: :autolink_id), repo_id: repo.id)
    case result
    when GH::Result::Error::NotFound
      deliver_error 404
    when GH::Result::Ok
      deliver_empty(status: 204)
    end
  end
end
