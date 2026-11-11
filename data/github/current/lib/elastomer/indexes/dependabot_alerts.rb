# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class DependabotAlerts < ::Elastomer::Index
    on_store_response :observe_store_response
    on_store_error :observe_store_error
    on_remove_response :observe_remove_response
    on_remove_error :observe_remove_error

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def self.mappings_hook
      {
        dependabot_alert: {
          _all: { enabled: false },
          _routing: { required: true },

          properties: {
            # Unified risk metadata for Dependabot alerts.
            risk_type: { type: "constant_keyword", value: "dependabot-alert" },

            # Immutable foreign keys
            repository_id: { type: "long" },
            vulnerability_id: { type: "long" },
            vulnerable_version_range_id: { type: "long" },

            # Mutable foreign keys
            owner_id: { type: "long" },
            assignee_ids: { type: "long" },

            # Immutable data

            ## VulnerableVersionRange
            ecosystem: { type: "keyword" },
            package_name: { type: "keyword", normalizer: "lowercase" },

            ## RepositoryVulnerabilityAlert
            id: { type: "long" },
            created_at: { type: "date" },
            manifest_path: {
              type: "text",
              analyzer: "path_split",
              fields: {
                # ES can't sort/aggregate on field type: "text", so we add a keyword sub-field
                keyword: { type: "keyword", ignore_above: 1024 }, # Underlying MySQL column length is capped at 1024 bytes.
              },
            },
            relationship: { type: "keyword" },

            # Mutable data

            ## Vulnerability
            severity: { type: "keyword" },
            # WARNING: If #severity_score starts returning a Float with more than _one_ decimal place of precision, we'll need to increase this scaling_factor accordingly.
            severity_score: { type: "scaled_float", scaling_factor: 10.0 },
            description: { type: "text", analyzer: "texty" },
            summary: { type: "text", analyzer: "texty" },
            classification: { type: "keyword" },
            vulnerability_scope: { type: "keyword" },

            ## VulnerableVersionRange
            has_patch: { type: "boolean" },

            ## CVEEPSS
            # Upstream EPSS results are calculated to 5 decimal place precision (0.00329). Raw data here: https://www.first.org/epss/data_stats
            epss_percentage: { type: "scaled_float", scaling_factor: 100_000.0 },

            ## RepositoryVulnerabilityAlert
            dependency_scope: { type: "keyword" },
            state: { type: "keyword" },
            resolution: { type: "keyword" },
            last_state_change_at: { type: "date" },
            updated_at: { type: "date" },
            search_index_updated_at: { type: "date" },
          },
        },
      }
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_dependabot_alerts,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            # The path_split tokenizer is used for searching. We opted for a custom tokenizer rather than
            # Elasticsearch's built-in `path_hierarchy` tokenizer because that's designed for filtering, so it doesn't
            # support inner matches: "a/b/c/d" matching "b/c". Additionally, it only tokenizes in one direction, so to
            # search both prefixes and suffixes, we'd need to index the field twice. The only downside is we don't get
            # the nice hierarchical tokens that `path_hierarchy` provides, but that doesn't really matter for this use case.
            path_split: {
              type: "custom",
              tokenizer: "path_split",
              filter: "lowercase",
            },
          },
          tokenizer: {
            path_split: {
              type: "pattern",
              pattern: "/",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    sig { params(type: String, response: T.nilable(T::Hash[T.any(Symbol, String), T.untyped])).returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
    def observe_store_response(type, response)
      return if response.nil?

      bulk_items = response.fetch("items", nil)
      if bulk_items.nil?
        # single document response.  Failures from calls in this flow
        # will be raised as errors and handled by the rescue block.
        GitHub.dogstats.increment(
          "dependabot_alerts.search.index",
          tags: ["action:index", "type:#{type}"]
        )
        return response
      end

      # bulk document response. Failures from individual operations will be
      # returned inline in the response.
      results_by_action = Hash.new { |h, k| h[k] = { success: 0, failed: 0 } }
      bulk_items.each do |item|
        item.each do |action, item_response|
          if item_response.key?("error")
            results_by_action[action][:failed] += 1
            report_error(item_response["error"])
          elsif !(200...300).cover?(item_response.fetch("status"))
            results_by_action[action][:failed] += 1
            report_error({ "type" => "status_code", "reason" => "#{item_response.fetch("status")}" })
          else
            results_by_action[action][:success] += 1
          end
        end
      end

      results_by_action.each do |action, results|
        if results[:success] > 0
          GitHub.dogstats.count(
            "dependabot_alerts.search.index",
            results[:success],
            tags: ["action:#{action}", "type:#{type}"]
          )
        end
        if results[:failed] > 0
          GitHub.dogstats.count(
            "dependabot_alerts.search.index.error",
            results[:failed],
            tags: ["action:#{action}", "type:#{type}", "error:unknown"]
          )
        end
      end
    end

    sig do params(type: String, error: T.any(
      ElastomerClient::Client::Error,
      ElastomerClient::Client::MultiDocumentRequestError
    )).void
    end
    def observe_store_error(type, error)
      # In the case of a client error, we treat the failure like a
      # single document request because we don't have any information to
      # determine the count of failures for a bulk document request
      GitHub.dogstats.increment(
        "dependabot_alerts.search.index.error",
        tags: ["action:index", "type:#{type}", "error:#{error.class.name&.underscore}"]
      )
    end

    sig { params(type: String, response: T.nilable(T::Hash[T.any(Symbol, String), T.untyped])).returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
    def observe_remove_response(type, response)
      return if response.nil?

      total_count = response.fetch("total", nil)
      if total_count.nil?
        # single delete response. Failures from calls in this flow
        # will be raised as errors and handled by the rescue block.
        GitHub.dogstats.increment(
          "dependabot_alerts.search.index",
          tags: ["action:delete", "type:#{type}"]
        )
        return response
      end

      # bulk delete response.  Failures from individual operations will be
      # determined based on the counts in the response.
      deleted_count = response["deleted"]
      GitHub.dogstats.count(
        "dependabot_alerts.search.index",
        deleted_count,
        tags: ["action:delete", "type:#{type}"]
      )

      if deleted_count < total_count
        GitHub.dogstats.increment(
         "dependabot_alerts.search.index.error",
          tags: ["action:delete", "type:#{type}", "error:not_all_documents_deleted"]
        )
      end

      if response["failures"].present? || response.fetch("version_conflicts", 0).to_i > 0
        raise ElastomerClient::Client::MultiDocumentRequestError.new(response)
      end
    end

    # Report failure causes in a formatted message to observability tools
    sig { params(cause: T.nilable(T.any(T::Hash[String, T.untyped], T::Array[T::Hash[String, T.untyped]]))).void }
    def report_error(cause)
      return if cause.nil?
      details = get_failure_details(cause)
      return if details.blank?

      error_message = details.each_with_index.reduce(T.let(nil, T.nilable(String))) do |message, (detail, index)|
        next detail[:message] if message.blank?

        prefix = if detail[:depth] > T.must(details[index - 1])[:depth]
          message + "\n#{"  " * T.must(details[index - 1])[:depth]}Caused by:\n"
        else
          message + "\n"
        end

        "#{prefix}#{"  " * detail[:depth]}#{detail[:message]}"
      end

      return if error_message.blank?

      Failbot.report(StandardError.new(error_message))
    end

    # Returns an array details about the failure cause and its root causes, if any.
    # Each cause will result in an entry with formatted message and the cause's depth in the
    # "root_cause" chain.
    sig { params(cause: T.nilable(T.any(T::Hash[String, T.untyped], T::Array[T::Hash[String, T.untyped]])), depth: Integer).returns(T::Array[{ message: String, depth: Integer }]) }
    def get_failure_details(cause, depth = 0)
      return [] if cause.blank?
      return cause.flat_map { |c| get_failure_details(c, depth) } if cause.is_a?(Array)

      [
        { message: "#{cause["type"]}: #{cause["reason"]}", depth: }
      ] + get_failure_details(cause["root_cause"], depth + 1)
    end

    sig do params(type: String, error: T.any(
      ElastomerClient::Client::Error,
      ElastomerClient::Client::MultiDocumentRequestError
    )).void
    end
    def observe_remove_error(type, error)
      # In the case of a client error, we treat the failure like a
      # single document request because we don't have any information to
      # determine the count of failures for a bulk document request

      # If this is a MultiDocumentRequestError, report each root cause to the error
      error_causes = case error
      when ElastomerClient::Client::MultiDocumentRequestError
        error.root_causes
      else
        [error.class.name&.underscore]
      end

      error_causes.each do |error_cause|
        GitHub.dogstats.increment(
          "dependabot_alerts.search.index.error",
          tags: ["action:delete", "type:#{type}", "error:#{error_cause}"]
        )
      end
    end

    sig { params(name: String, cluster: T.nilable(String)).returns(Elastomer::Indexes::DependabotAlerts) }
    def self.searcher(name = ::Elastomer.env.index_name("dependabot-alerts"), cluster = nil)
      if cluster.nil? && name.start_with?("dependabot-alerts")
        cluster = ::Elastomer.router.cluster_for_index(name)
      end
      new(name, cluster)
    end
  end
end
