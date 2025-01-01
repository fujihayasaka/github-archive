# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Issues index contains documents for issues (and their comments)
  # These documents are searchable within this index.
  #
  class Issues < ::Elastomer::Index

    # Defines the mappings for the 'issue' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
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
                body: { type: "text", analyzer: "texty" },
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

    # Returns the Array of valid aliases for this index type.
    def self.aliases
      [::Elastomer.env.logical_index_name(self),
        ::Elastomer.env.index_name("issues-search")]
    end

    # Public: Returns an Issues index index configured to search the
    # `issues-search` alias. This alias spans the `issues` search index and
    # the `pull-requests` search index enabling us to search both with one
    # query.
    #
    # name    - The index name as a String or Symbol
    # cluster - The cluster name as a String or Symbol
    #
    # Returns an Issues search index instance.
    def self.searcher(name = ::Elastomer.env.index_name("issues-search"), cluster = nil)
      if cluster.nil? && name.start_with?("issues-search")
        cluster = ::Elastomer.router.cluster_for_index(name.sub(/\Aissues-search/, "issues"))
      end
      new(name, cluster)
    end

    # Public: Returns an Issues index index configured to search the
    # `issues` index.
    #
    # Returns an Issues search index instance.
    def self.by_type(type)
      index = case type
      when "pr"
        "pull-requests"
      when "issue"
        "issues"
      else
        "issues-search"
      end
      name = ::Elastomer.env.index_name(index)
      cluster = ::Elastomer.router.cluster_for_index(name)
      new(name, cluster)
    end

    # Purge all documents for the given user from this search index. This will
    # remove all issues where the user is (a) the author of the
    # document or (b) has commented on the document.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      begin
        delete_by_query(
            { term: { author_id: user.id } }, type: %w[issue]
        )
      rescue StandardError => boom # rubocop:todo Lint/GenericRescue
        Failbot.report(boom.with_redacting!)
      end

      issue_ids = ActiveRecord::Base.connected_to(role: :reading) { user.interacted_issue_ids }
      issue_ids.each do |issue_id|
        begin
          store Elastomer::Adapters::Issue.create(issue_id)
        rescue StandardError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!, issue_id: issue_id)
        end
      end

      self
    end

    # Restore all documents for given user in this search index. Any Issue
    # will be re-indexed where the user is (a) the author or (b) has
    # commented on the item.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      issue_ids = ActiveRecord::Base.connected_to(role: :reading) { user.interacted_issue_ids }
      issue_ids.each do |issue_id|
        begin
          store Elastomer::Adapters::Issue.create(issue_id)
        rescue StandardError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!, issue_id: issue_id)
        end
      end

      self
    end

  end  # Issues
end  # Elastomer::Indexes
