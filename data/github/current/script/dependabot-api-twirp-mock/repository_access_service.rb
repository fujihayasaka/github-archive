# frozen_string_literal: true

require "proto-dependabot-api"

require_relative "../../lib/github/cache"

module RepositoryAccessService
  def mock_get_repository_access(req, res)
    request_proto = decode_protobuf_request(req, DependabotApi::V1::GetRepositoryAccessRequest)
    return json_response(res, { error: "Invalid Protobuf format" }, 400) if request_proto.nil?

    owner_id = request_proto.owner_github_id
    if owner_id.nil?
      log_to_console("Missing required parameters")
      return json_response(res, { error: "Missing required parameters: owner_github_id" }, 422)
    end

    # Log the incoming parameters
    log_to_console("Params: owner_github_id=#{owner_id}")

    key = "dependabot-api-twirp-mock:repository_access:#{owner_id}"
    log_to_console("Cache Key: #{key}")

    cached_repository_ids = GitHub::Cache::ClientBuilder.client_for(partition: :global).get(key)
    cached_repository_ids = cached_repository_ids.blank? ? [] : JSON.parse(cached_repository_ids)
    log_to_console("Cached Repository IDs: #{cached_repository_ids}")

    # Create the Protobuf response
    proto_response(res, DependabotApi::V1::GetRepositoryAccessResponse.new(
      access_editable: true,
      repository_github_ids: cached_repository_ids
    ))
  end

  def mock_set_selected_repositories(req, res)
    request_proto = decode_protobuf_request(req, DependabotApi::V1::SetSelectedRepositoriesRequest)
    return json_response(res, { error: "Invalid Protobuf format" }, 400) if request_proto.nil?

    owner_id = request_proto.owner_github_id
    repository_ids = request_proto.repository_github_ids.to_a

    if owner_id.nil?
      log_to_console("Missing required parameters")
      return json_response(res, { error: "Missing required parameters: owner_github_id, repository_github_ids" }, 422)
    end

    log_to_console("Params: owner_github_id=#{owner_id}, repository_github_ids=#{repository_ids}")

    key = "dependabot-api-twirp-mock:repository_access:#{owner_id}"
    log_to_console("Cache Key: #{key}")

    GitHub::Cache::ClientBuilder.client_for(partition: :global).set(key, repository_ids.to_json)

    # Create the Protobuf response
    proto_response(res, DependabotApi::V1::SetSelectedRepositoriesResponse.new)
  end

  def mock_repository_access_service(server)
    server.mount_proc "/twirp/DependabotApi.v1.RepositoryAccessService/GetRepositoryAccess", &method(:mock_get_repository_access)
    server.mount_proc "/twirp/DependabotApi.v1.RepositoryAccessService/SetSelectedRepositories", &method(:mock_set_selected_repositories)
  end
end
