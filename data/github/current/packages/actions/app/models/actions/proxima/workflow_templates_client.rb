# typed: true
# frozen_string_literal: true

require "graphql/client"
require "graphql/client/http"

class Actions::Proxima::WorkflowTemplatesClient

  STATS_KEY_PREFIX = "actions.proxima.workflow.templates.templates_client"

  def initialize(repo_owner:, repo_name:, connection:, token_generator:)
    @repo_owner = repo_owner
    @repo_name = repo_name

    @token_generator = token_generator || Actions::Proxima::TokenGenerator.new
    @connection = connection
  end

  attr_reader :repo_owner, :repo_name, :token_generator, :connection

  def fetch_templates(sha, folders)
    GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.fetch_templates")
    response = T.let(nil, T.untyped)

    GitHub.dogstats.distribution_time("#{STATS_KEY_PREFIX}.fetch_templates.duration") do
      query = files_query(sha, folders)
      response = graphql_request(query, {
        repo_owner: repo_owner,
        repo_name: repo_name,
      })
      GitHub.dogstats.gauge("#{STATS_KEY_PREFIX}.fetch_templates.response_size", response.body&.size || 0)

      parsed_response = GitHub::JSON.decode(response.body)

      if parsed_response.has_key?("errors")
        raise Actions::Proxima::WorkflowTemplatesError.new("GraphQL response contained errors",
          url: response.env.url,
          status: response.status,
          errors: parsed_response["errors"]
        )
      end

      parsed_response.dig("data", "repository")
    end
  rescue Yajl::ParseError => e
    GitHub.dogstats.increment("#{STATS_KEY_PREFIX}.fetch_templates.error")
    raise Actions::Proxima::WorkflowTemplatesError.new("failed to parse response", url: response.env.url, body: response.body, status: response.status)
  end

  def files_query(sha, folders)
    template_folders = folders_with_aliases(folders)

    template = <<~'GRAPHQL'
    query ($repo_owner: String!, $repo_name: String!) {
      repository(name: $repo_name, owner: $repo_owner) {
      <%- template_folders.each do |(folder, query_alias)| -%>
        <%= query_alias %>:object(expression: "<%= "#{sha}:#{folder}" %>") {
          ...FilesWithContentsFragment
        }
      <%- end -%>
      }
    }

    fragment FilesWithContentsFragment on Tree {
      files:entries {
        path,
        object {
          ... on Blob {
            text,
            isTruncated
          }
        }
      }
    }
    GRAPHQL

    ERB.new(template, trim_mode: "-").result(binding)
  end

  private

  def graphql_request(query, variables)
    proxima_service_identity_token = token_generator.generate_proxima_service_identity_token

    response = connection.post do |req|
      req.url URI(GitHub.dotcom_graphql_api_prefix)
      req.headers["X-GitHub-PSI-JWT"] = proxima_service_identity_token
      req.headers["Content-Type"] = "application/json"
      req.body = JSON[{
        query: query,
        variables: variables,
      }]
    end

    if !response.success?
      raise Actions::Proxima::WorkflowTemplatesError.new("GraphQL request failed", url: response.env.url, body: response.body, status: response.status)
    end

    response
  end

  def folders_with_aliases(folders)
    folders.each_with_object([]) do |folder, acc|
      acc << [folder, folder_alias(folder)]

      if folder != "icons"
        properties_folder = "#{folder}/properties"
        acc << [properties_folder, folder_alias(properties_folder)]
      end
    end
  end

  def folder_alias(folder_name)
    folder_name.gsub(/[^\w]/, "")
  end
end
