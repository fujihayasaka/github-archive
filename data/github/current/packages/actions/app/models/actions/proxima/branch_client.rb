# typed: true
# frozen_string_literal: true

class Actions::Proxima::BranchClient
  extend T::Sig

  STATS_KEY_PREFIX = "actions.proxima.workflow.templates.branch_client"

  def initialize(connection:, token_generator:)
    @connection = connection
    @token_generator = token_generator
  end

  attr_reader :connection, :token_generator

  sig { params(repo_nwo: String, branch_name: String).returns(String) }
  def sha_for_branch(repo_nwo, branch_name)
    GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.sha_for_branch")
    response = T.let(nil, T.untyped)

    GitHub.dogstats.distribution_time("#{STATS_KEY_PREFIX}.sha_for_branch.duration") do
      branch_uri = "/repos/#{repo_nwo}/git/trees/#{branch_name}"

      response = authenticated_request(branch_uri)
      parsed_response = GitHub::JSON.decode(response.body)

      if parsed_response["sha"].blank?
        raise Actions::Proxima::WorkflowTemplatesError.new("parsed response didn't contain sha",
          url: response.env.url,
          status: response.status,
          body: response.body,
        )
      end

      parsed_response["sha"]
    end
  rescue Yajl::ParseError => e
    GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.sha_for_branch.error")
    raise Actions::Proxima::WorkflowTemplatesError.new("failed to parse response",
      url: response.env.url,
      status: response.status,
      body: response.body,
    )
  end

  private

  def authenticated_request(path, params = {})
    uri = URI(path)
    uri.query = params.to_query
    access_token = token_generator.generate_token

    response = connection.get do |req|
      req.url uri.to_s
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Content-Type"] = "application/json"
    end

    if !response.success?
      raise Actions::Proxima::WorkflowTemplatesError.new("request failed",
        url: response.env.url,
        status: response.status,
        body: response.body,
      )
    end

    response
  end
end
