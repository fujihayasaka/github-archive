require "github-proto-repositories"
require_relative "twirp_client"

module Monolith
  # A client to the Repositories twirp API in the github monolith
  #
  # The server implementation of this is at
  # https://github.com/github/github/blob/49f8cde1d3f8f3b022ebb59df1af9ad338d54d12/app/api/internal/twirp/repositories/v1/repositories_api_handler.rb
  class Repositories < TwirpClient
    def initialize(service: "github-repositories")
      super
    end

    # Find repositories by Id
    def find_repositories(ids)
      resp = client.find_repositories(ids: ids)
      unwrap_response(resp)
    end

    # Find repositories by NWO.
    def find_repositories_by_name(nwos)
      resp = client.find_repositories_by_name(nwos: nwos)
      unwrap_response(resp)
    end

    private

    def unwrap_response(response)
      # setting whole `response.error` as msg here can cause log spam!
      # response.error.meta.body is the entire resp body!
      raise Error, response.error&.message if response.error
      response.data.repositories.map { |d| to_repo(d) }
    end

    def to_repo(data)
      ::Repository.new(github_repository_id: data.id,
                       github_owner_id: data.owner_id,
                       nwo: "#{data.owner_login}/#{data.name}",
                       public: data.visibility == :VISIBILITY_PUBLIC)
    end

    def client
      @client ||= GitHub::Proto::Repositories::V1::RepositoriesAPIClient.new(connection)
    end
  end
end
