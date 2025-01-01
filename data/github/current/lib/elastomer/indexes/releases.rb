# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The Releases index contains documents for releases. These documents are
  # searchable within this index.
  #
  class Releases < ::Elastomer::Index

    # Defines the mappings for the 'release' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        release: {
          _all: { enabled: false },
          properties: {
            tag_name: {
              type: "text",
              fields: {
                raw: { type: "keyword" }
              },
              analyzer: "tag_name"
            },
            version_major: { type: "integer" },
            version_minor: { type: "integer" },
            version_patch: { type: "integer" },
            name: { type: "text", analyzer: "title" },
            body: { type: "text", analyzer: "texty" },
            draft: { type: "boolean" },
            prerelease: { type: "boolean" },
            repo_id: { type: "integer" },
            author_id: { type: "integer" },
            # Release.created_at has the target datetime (either the commit or annotated tag).
            created_at: { type: "date" },
            # In order to sort by day and then by semver, we need a column without time:
            created_day: { type: "date" },
            updated_at: { type: "date" },
            published_at: { type: "date" }
          }
        }
      }
    end

    # Settings for a Releases search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_releases,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            title: {
              tokenizer: "standard",
              filter: %w[lowercase asciifolding],
            },
            tag_name: {
              type: "custom",
              tokenizer: "tag_name",
              filter: %w[lowercase],
            },
          },
          tokenizer: {
            # Tokenize tag names like "v1.2.0" so we can search by v1, v1.2, v1.2.0.
            tag_name: {
              type: "path_hierarchy",
              delimiter: ".",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Purge all releases where the user is the author.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      delete_by_query({ term: { author_id: user.id } }, type: "release")
      self
    end

    # Restore all releases where the user is the owner.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      ::Releases::Public.load_by_author(user.id).each do |release_id|
        begin
          store Elastomer::Adapters::Release.create(release_id)
        rescue => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!, "gh.release.id": release_id)
        end
      end
      self
    end
  end
end
