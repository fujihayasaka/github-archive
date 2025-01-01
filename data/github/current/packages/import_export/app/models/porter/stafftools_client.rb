# typed: true
# frozen_string_literal: true

module Porter
  # Accesses an internal API in porter to get information to show in stafftools.
  class StafftoolsClient
    extend Porter::Urls

    def self.get_import_status(repository:, env:)
      repository_url = porter_admin_repository_url(
        repository: repository,
        options:    { json: true },
      )

      options = {
        repository_url: repository_url,
        request_id:     env["HTTP_X_GITHUB_REQUEST_ID"],
      }

      new(options).get_status
    end

    def initialize(options)
      @repository_url = options.fetch(:repository_url)
      @request_id = options.fetch(:request_id)
      @auth_token = options.fetch(:internal_api_token) { GitHub.porter_internal_api_token }
      @timeout = options.fetch(:timeout, 1)
    end

    attr_reader :repository_url, :request_id, :auth_token, :timeout

    def get_status
      GitHub::Timer.timeout(timeout, Faraday::TimeoutError) do
        response = faraday.get(repository_url)
        GitHub.logger.info({
          "code.namespace" => "PorterStafftoolsClient",
          "code.function" => "get_status",
          "gh.migration_tools.migration.type" => "repo",
          "gh.repo.url" => repository_url,
          "gh.migration_tools.migration.response" => response.status
        })
        if response.success?
          json = GitHub::JSON.load(response.body)
          if json["found"]
            [:ok, json.slice("status", "failed_step")]
          else
            [:not_found, nil]
          end
        else
          nil
        end
      end
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report!(e, "gh.migration_tools.migration.repository.url" => repository_url)
      nil
    end

    private

    def faraday
      @faraday ||= build_faraday
    end

    def build_faraday
      options = {
        url: repository_url,
        headers: {
          "Accept" => "application/vnd.porter.v1+json",
          "X-GitHub-Request-Id" => request_id,
        },
        request: {
          timeout: timeout,
          open_timeout: 5,
        },
      }
      Faraday.new(options) do |c|
        c.basic_auth(auth_token, "github")
        c.adapter Faraday.default_adapter
      end
    end
  end
end
