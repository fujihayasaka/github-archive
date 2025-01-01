# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class IssuesSemantic < ::Elastomer::Index

    def initialize(name = nil, cluster = nil)
      super

      # Below is copied from ::Elastomer::Router#initialize where clients are created.
      # Only thing I changed here are the read_timeout and open_timeout values.
      # This is to reduce the noises during repair job where inference endpoint causing longer request time.
      cluster_config = ::Elastomer.config.clusters[@cluster_name]
      opts = {
        read_timeout: 61.seconds.to_i, # Elasticsearch thinks it has 1m to process the request.
        open_timeout: 1.second.to_i, # was 0.3s
        url: cluster_config.fetch(:url),
        adapter: :typhoeus,
        opaque_id: true,
        max_request_size: 25.megabytes,
        strict_params: true,
        es_version: cluster_config[:es_version],
        compress_body: cluster_config[:compress_body],
        basic_auth: cluster_config[:basic_auth],
        token_auth: cluster_config[:token_auth],
      }
      stamp_name = ::Elastomer::Router.stamp
      stamp_prefix = !stamp_name.nil? ? "#{stamp_name}_" : ""
      @client = ::ElastomerClient::Client.new(**opts) do |connection|
        service_name = "elasticsearch_#{stamp_prefix + @cluster_name}"

        retry_options = {
          client_name: service_name,
          stats: ::GitHub.dogstats,
          max: 1,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2,
          methods: ::Elastomer::Router::RETRYABLE_METHODS,
          exceptions: Faraday::Request::Retry::DEFAULT_EXCEPTIONS + [Faraday::ConnectionFailed]
        }
        connection.use GitHub::FaradayMiddleware::Retries, retry_options

        connection.use GitHub::FaradayMiddleware::Resilient,
          name: service_name,
          options: ::Elastomer::Router.resilient_properties do |env|
            cb_status = env[:resilient_circuit].properties.force_open ? "forced open" : "tripped"
            env.body = %Q({"error": "circuit breaker #{cb_status} in #{@cluster_name} cluster"})
          end

        connection.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: service_name
      end

      name = GitHub.get_search_index_override.presence || name.presence || self.class.index_name
      @index = @client.index(name)
      @docs = @index.docs
      @template = @client.template(name)
      @cluster = @client.cluster
    rescue ElastomerClient::Client::ServerError => error
      @server_error = error
    end

    def self.mappings_hook
      {
        issue: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            title: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" }
              },
              analyzer: "texty",
              copy_to: %w[title_semantic semantic_search_field],
            },
            body: { type: "text", analyzer: "texty", copy_to: %w[body_semantic semantic_search_field] },
            issue_id: { type: "long" },
            author_id: { type: "long" },
            num_comments: { type: "integer" },
            num_reactions: { type: "integer" },
            repo_id: { type: "long" },
            business_id: { type: "integer" },
            network_id: { type: "integer" },
            public: { type: "boolean" },
            archived: { type: "boolean" },
            state: { type: "keyword" },
            number: { type: "integer" },
            labels: { type: "keyword" },
            issue_type_name: { type: "keyword" },
            language: { type: "keyword" },
            language_id: { type: "integer", doc_values: true },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            closed_at: { type: "date" },
            locked_at: { type: "date" },
            locked: { type: "boolean" },
            assignee_id: { type: "long" },
            milestone_num: { type: "integer" },
            milestone_title: { type: "keyword" },
            project_ids: { type: "integer" },
            memex_project_ids: { type: "long" },
            mentioned_user_ids: { type: "long" },
            mentioned_team_ids: { type: "long" },
            participating_user_ids: { type: "long" },
            has_closing_reference: { type: "boolean" },
            reactions: {
              type: "object",
              properties: {
                "+1": { type: "integer" },
                "-1": { type: "integer" },
                smile: { type: "integer" },
                thinking_face: { type: "integer" },
                heart: { type: "integer" },
                tada: { type: "integer" }
              }
            },
            comments: {
              type: "object",
              properties: {
                comment_id: { type: "long" },
                comment_type: { type: "keyword" },
                body: { type: "text", analyzer: "texty", copy_to: %w[comment_body_semantic semantic_search_field] },
                author_id: { type: "long" },
                created_at: { type: "date" },
                updated_at: { type: "date" },
                reactions: {
                  type: "object",
                  properties: {
                    "+1": { type: "integer" },
                    "-1": { type: "integer" },
                    smile: { type: "integer" },
                    thinking_face: { type: "integer" },
                    heart: { type: "integer" },
                    tada: { type: "integer" }
                  }
                }
              }
            },
            parent_issue: { type: "keyword" },
            sub_issue: { type: "keyword" },
            title_semantic: { type: "semantic_text", inference_id: "azure-openai-embeddings" },
            body_semantic: { type: "semantic_text", inference_id: "azure-openai-embeddings" },
            comment_body_semantic: { type: "semantic_text", inference_id: "azure-openai-embeddings" },
            semantic_search_field: { type: "semantic_text", inference_id: "azure-openai-embeddings" },
          }
        }
      }
    end

    # Settings for an Issues search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_issues,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          max_result_window: 50000,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            index_ngram_text: {
              tokenizer: "standard",
              filter: %w[lowercase ngram_text],
            },
            search_ngram_text: {
              tokenizer: "standard",
              filter: "lowercase",
            },
          },
          filter: {
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
              side: "front",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end
  end
end
