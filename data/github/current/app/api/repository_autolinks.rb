# typed: true
# frozen_string_literal: true

class Api::RepositoryAutolinks < Api::App
  include ReceiveSchemaWithOpenApi
  include Repositories::Domain::Provider

  # Get all autolinks of a repo
  get "/repositories/:repository_id/autolinks", operation_id: "repos/list-autolinks" do
    repo = find_repo!
    control_access :list_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true

    if GitHub.flipper[:autolink_new_domain].enabled?(current_user)
      autolinks = repositories_domain.key_links.list_for_repo(repo.id)
      deliver :autolink_hash, autolinks
    else
      autolinks = KeyLinks::Public.find_all_with_owner!(repo)
      # We don't do pagination here as the maximum number of autolinks per repository is 500
      deliver :autolink_hash, autolinks
    end
  end

  # Get a single autolink by ID
  get "/repositories/:repository_id/autolinks/:autolink_id", operation_id: "repos/get-autolink" do
    repo = find_repo!
    control_access :read_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    autolink = repositories_domain.key_links.by_id(int_id_param!(key: :autolink_id), repo_id: repo.id)
    deliver :autolink_hash, autolink
  end

  # Create a new autolink
  post "/repositories/:repository_id/autolinks", operation_id: "repos/create-autolink" do
    repo = find_repo!
    control_access :create_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    data = receive_with_openapi

    if GitHub.flipper[:autolink_new_domain].enabled?(current_user)
      attributes = Repositories::CreateKeyLinkAttributes.new(
        key_prefix: data["key_prefix"],
        url_template: data["url_template"]
      )

      attributes.is_alphanumeric = data["is_alphanumeric"] unless data["is_alphanumeric"].nil?

      result = repositories_domain.key_links.create(attributes, repo_id: repo.id)
      case result
      when GH::Result::Ok
        deliver :autolink_hash, result.value, status: 201
      when GH::Result::Error::Validation
        deliver_error 422, errors: result.model.errors, documentation_url: @documentation_url
      when GH::Result::Error
        raise "Unexpected error: #{result.message}"
      else
        raise "Unexpected result: #{result.class}"
      end
    else
      autolink = repo.key_links.build \
        key_prefix: data["key_prefix"],
        url_template: data["url_template"],
        is_alphanumeric: data["is_alphanumeric"].nil? ? true : data["is_alphanumeric"]

      begin
        if autolink.save
          deliver :autolink_hash, autolink, status: 201
        else
          deliver_error 422,
            errors: autolink.errors,
            documentation_url: @documentation_url
        end
      rescue ActiveRecord::RecordNotUnique
        deliver_error! 422, message: "key_prefix is already in use"
      end
    end
  end

  # Delete an autolink
  delete "/repositories/:repository_id/autolinks/:autolink_id", operation_id: "repos/delete-autolink" do
    repo = find_repo!
    control_access :delete_repo_autolinks, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    if GitHub.flipper[:autolink_new_domain].enabled?(current_user)
      result = repositories_domain.key_links.destroy(int_id_param!(key: :autolink_id), repo_id: repo.id)

      case result
      when GH::Result::Error::NotFound
        deliver_error 404
      when GH::Result::Ok
        deliver_empty(status: 204)
      when GH::Result::Error
        raise "Unexpected result: #{result.message}"
      else
        raise "Unexpected result: #{result.class}"
      end
    else
      autolink = repositories_domain.key_links.by_id(int_id_param!(key: :autolink_id), repo_id: repo.id)
      if autolink
        KeyLinks::Public.destroy_by_id(autolink.id)
        deliver_empty(status: 204)
      else
        deliver_error 404
      end
    end
  end

end
