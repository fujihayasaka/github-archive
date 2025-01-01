# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The WorkflowRuns index contains documents for workflow runs.
  # These documents are searchable within this index.
  #
  class WorkflowRuns < ::Elastomer::Index

    # Defines the mappings for the 'workflow_run' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        workflow_run: {
          _all: { enabled: false },
          properties: {
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "lowercase_ngram", search_analyzer: "lowercase" }
              },
              analyzer: "lowercase"
            },
            workflow_run_id: { type: "long" },
            check_suite_id: { type: "long" },
            status: { type: "text" },
            conclusion: { type: "text" },
            head_branch: { type: "keyword" },
            head_sha: { type: "text" },
            event: { type: "keyword" },
            action: { type: "text" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            repo_id: { type: "long" },
            head_repo_id: { type: "long" },
            workflow_name: { type: "text" },
            workflow_id: { type: "long" },
            creator: { type: "text" },
            pusher: { type: "text" },
            is: { type: "text" },
            actor: { type: "text" },
            title: { type: "text" },
            lab: { type: "boolean" },
            rank: { type: "double" },
            actor_id: { type: "long" },
            user_hidden: { type: "boolean" }
          }
        }
      }
    end

    # Settings for a WorkflowRuns search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_workflow_runs,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            name: {
              tokenizer: "standard",
              filter: %w[lowercase p_asciifolding],
            },
            lowercase: {
              tokenizer: "whitespace",
              filter: %w[lowercase],
            },
            lowercase_ngram: {
              tokenizer: "whitespace",
              filter: %w[lowercase ngram_text],
            },
          },
          filter: {
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
            },
            p_asciifolding: {
              type: "asciifolding",
              preserve_original: true,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Purge the workflow run from the search index.
    #
    # workflow run - The WorkflowRun for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_workflow_run(workflow_run)
      docs.delete type: "workflow_run", id: workflow_run.id
      self
    end

    # Restore the workflow run to the search index.
    #
    # workflow_run - The WorkflowRun for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_workflow_run(workflow_run)
      store Elastomer::Adapters::WorkflowRun.create(workflow_run)
      self
    end

    # Reindexes all workflow runs where the given user's id matches the workflow_run's actor_id
    # Used when a user is marked spammy
    #
    # Returns this search index.
    def purge_user(user)
      reindex_user_workflow_runs(user)
    end

    # Reindexes all workflow runs where the given user's id matches the workflow_run's actor_id
    # Used when a user is un-marked spammy
    #
    # Returns this search index.
    def restore_user(user)
      reindex_user_workflow_runs(user)
    end

    def reindex_user_workflow_runs(user)
      Actions::WorkflowRun.annotate("cross-shard-query-exempted-permanent").where(actor_id: user.id).in_batches do |batch|
        workflow_run_ids = batch.pluck(:id)
        workflow_run_ids.each do |workflow_run_id|
          begin
            store Elastomer::Adapters::WorkflowRun.create(workflow_run_id)
          rescue StandardError => boom # rubocop:todo Lint/RescueException
            Failbot.report(boom.with_redacting!, workflow_run_id: workflow_run_id)
          end
        end
      end

      self
    end
  end  # WorkflowRuns
end  # Elastomer::Indexes
