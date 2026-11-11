
# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The PullRequests index contains documents for pull requests (and their
  # comments).
  #
  class PullRequests < ::Elastomer::Index
    def self.default_settings
      if !GitHub.single_or_multi_tenant_enterprise?
        {
          index: {
            merge: {
              policy: {
                max_merged_segment: "15gb",
              },
            },
          },
        }
      else
        {}
      end
    end

    # Defines the mappings for the 'pull_request' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      if GitHub.enterprise?
        self.base_mappings
      else
        self.base_mappings.deep_merge(self.semantic_mappings)
      end
    end

    # Returns the base Elasticsearch mappings for pull request documents.
    def self.base_mappings
      {
        pull_request: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            title: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" }
              },
              analyzer: "texty"
            },
            body: { type: "text", analyzer: "texty" },
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
            language: { type: "keyword" },
            language_id: { type: "integer", doc_values: true },
            head_ref: { type: "keyword" },
            base_ref: { type: "keyword" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            closed_at: { type: "date" },
            locked_at: { type: "date" },
            locked: { type: "boolean" },
            assignee_id: { type: "long" },
            requested_reviewer_ids: { type: "long" },
            requested_reviewer_team_ids: { type: "long" },
            reviewer_team_ids: { type: "long" },
            reviewer_ids: { type: "long" },
            review_status: { type: "keyword" },
            reviewable_state: { type: "keyword" },
            milestone_num: { type: "integer" },
            milestone_title: { type: "keyword" },
            milestone_prio: { type: "unsigned_long" },
            project_ids: { type: "integer" },
            memex_project_ids: { type: "long" },
            mentioned_user_ids: { type: "long" },
            mentioned_team_ids: { type: "long" },
            has_closing_reference: { type: "boolean" },
            status: { type: "keyword" },
            merged: { type: "boolean" },
            queued: { type: "boolean" },
            merged_at: { type: "date" },
            mergeability: { type: "keyword" },
            merge_commit: { type: "keyword" },
            additions: { type: "integer" },
            deletions: { type: "integer" },
            changed_files: { type: "integer" },
            num_commits: { type: "integer" },
            commits: { type: "keyword" },
            draft: { type: "boolean" },
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
                body: { type: "text", analyzer: "texty" },
                author_id: { type: "long" },
                created_at: { type: "date" },
                updated_at: { type: "date" },
                dead: { type: "boolean" },
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
            }
          }
        }
      }
    end

    # Returns additional Elasticsearch mappings for semantic search fields on pull request documents.
    def self.semantic_mappings
      inference_id = GitHub.es_issues_prs_inference_id
      dimensions = GitHub.es_issues_prs_embedding_dimensions
      similarity = GitHub.es_issues_prs_embedding_similarity

      base_vector_config = {
        type: "semantic_text",
        inference_id: inference_id,
        model_settings: {
          task_type: "text_embedding",
          dimensions: dimensions,
          similarity: similarity,
          element_type: "float"
        },
        index_options: {
          dense_vector: {
            type: "bbq_hnsw",
            m: 16,
            ef_construction: 100,
            rescore_vector: {
              oversample: 3.0
            }
          }
        }
      }

      {
        pull_request: {
          properties: {
            title_dense_vector: base_vector_config.deep_dup,
            body_dense_vector: base_vector_config.deep_dup
          }
        }
      }
    end

    # Settings for a PullRequests search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_pull_requests,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
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
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Returns the Array of valid aliases for this index type.
    def self.aliases
      [
        ::Elastomer.env.logical_index_name(self),
        ::Elastomer.env.index_name("issues-search")
      ]
    end

    # Purge all documents for the given user from this search index. This will
    # remove all pull requests where the user is (a) the author of the
    # document or (b) has commented on the document.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      begin
        delete_by_query(
          { term: { author_id: user.id } }, type: "pull_request"
        )
      rescue StandardError => boom # rubocop:todo Lint/RescueException
        Failbot.report(boom.with_redacting!)
      end

      user.interacted_pull_request_ids.each do |pull_request_id| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        begin
          store Elastomer::Adapters::PullRequest.create(pull_request_id)
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom.with_redacting!, "gh.pull_request.id": pull_request_id)
        end
      end

      self
    end

    # Restore all documents for given user in this search index. Any pull
    # request or will be re-indexed where the user is (a) the author or (b)
    # has commented on the item.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      user.interacted_pull_request_ids.each do |pull_request_id| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        begin
          store Elastomer::Adapters::PullRequest.create(pull_request_id)
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom.with_redacting!, "gh.pull_request.id": pull_request_id)
        end
      end

      self
    end

    # Search the Pull Request index for merged PRs including a commit
    #
    # commit - Commit object to search for
    # limit  - number of hits to return at most
    #          (optional, defaults to 10)
    #
    # Returns a Hash with keys:
    #   :hits      - Array of hit Hashes
    #   :timed_out - whether the search timed out
    def search_merged_including_commit(commit, limit = 10)
      query = {
        query: { constant_score: {
          filter: { bool: { must: [
            { term: { commits: commit.oid } },
            { terms: { repo_id: [commit.repository&.id.to_i, commit.repository&.parent_id].compact } },
            { term: { merged: true } },
          ] } },
        } },
        _source: %w[merged_at repo_id],
        sort: [{ merged_at: "asc" }],
        size: limit,
      }

      result = search(query,
        type: "pull_request"
      )

      {
        hits: result["hits"]["hits"],
        timed_out: result["timed_out"],
      }
    end

    # Search the Pull Request index for merged PRs including any of the given commits.
    # This is a batched version of search_merged_including_commit that issues a single
    # ES query instead of N queries for N commits.
    #
    # commits  - Array of Commit objects to search for
    # repo_ids - Array of repository IDs to filter by (typically [repo_id, parent_id])
    #
    # Returns a Hash with keys:
    #   :hits_by_oid - Hash mapping commit oid => Array of hit Hashes
    #   :timed_out   - whether the search timed out
    def search_merged_including_commits(commits, repo_ids)
      oids = commits.map(&:oid).uniq
      return { hits_by_oid: {}, timed_out: false } if oids.empty?

      query = {
        query: { constant_score: {
          filter: { bool: { must: [
            { terms: { commits: oids } },
            { terms: { repo_id: repo_ids.compact } },
            { term: { merged: true } },
          ] } },
        } },
        size: 0,
        aggs: {
          by_commit: {
            terms: { field: "commits", include: oids, size: oids.length },
            aggs: {
              top_prs: {
                top_hits: {
                  _source: %w[merged_at repo_id],
                  sort: [{ merged_at: "asc" }],
                  size: 2,
                },
              },
            },
          },
        },
      }

      result = search(query,
        type: "pull_request"
      )

      timed_out = result["timed_out"]

      # Build hits_by_oid from the per-commit aggregation buckets.
      # Each bucket contains the top 2 PRs for that commit oid, sorted
      # by merged_at, matching the per-commit query behavior exactly.
      hits_by_oid = {}
      oids.each { |oid| hits_by_oid[oid] = [] }

      buckets = result.dig("aggregations", "by_commit", "buckets") || []
      buckets.each do |bucket|
        oid = bucket["key"]
        next unless hits_by_oid.key?(oid)
        hits_by_oid[oid] = bucket.dig("top_prs", "hits", "hits") || []
      end

      { hits_by_oid: hits_by_oid, timed_out: timed_out }
    end

    # Search the Pull Request index for a PR merged by a specific commit.
    # We expect only one result but allow for the possibility finding
    # multiple results.
    #
    # repository_id    - The ID of the commit's repository. Also the ID of the
    #                    repository a matching pull request must belong to.
    # base_branch_name - The branch name committed to and the base ref of a
    #                    matching pull request.
    # oid              - The full SHA of the merge commit.
    #
    # Returns a two-element Array with a Symbol result and an Integer pull
    # request ID (if found).
    #
    # Possible results:
    #   :found          - A single pull request was found and its ID is
    #                     returned.
    #   :not_found      - No pull requests were found. No ID is returned.
    #   :multiple_found - Multiple pull requests were found. The most
    #                     recently merged pull request ID is returned.
    #   :timed_out      - The search timed out. No ID is returned.
    sig do
      params(
        repository_id: Integer,
        base_branch_name: String,
        oid: String,
      ).returns([Symbol, T.nilable(Integer)])
    end
    def id_by_merge_commit(repository_id:, base_branch_name:, oid:)
      result = search({
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { repo_id: repository_id } },
                  { term: { base_ref: base_branch_name } },
                  { term: { merge_commit: oid } },
                  { term: { merged: true } },
                ],
              },
            },
          },
        },
        sort: [{ merged_at: "desc" }], # Prefer the latest.
        _source: false, # We only need the ID.
        size: 1, # We only want the first result.
      })

      return [:timed_out, nil] if result["timed_out"]

      hits = result["hits"] || {}
      total = Elastomer::UpgradeShims.get_total_hits(hits)
      id = hits.dig("hits", 0, "_id")&.to_i

      if total == 1
        [:found, id]
      elsif total > 1
        [:multiple_found, id]
      else
        [:not_found, nil]
      end
    end
  end  # PullRequests
end  # Elastomer::Indexes
