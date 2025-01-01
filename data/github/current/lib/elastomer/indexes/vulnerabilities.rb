# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class Vulnerabilities < ::Elastomer::Index
    def self.mappings_hook
      {
        topic: {
          _all: { enabled: false },
          properties: {
            description: { type: "text", analyzer: "texty" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            published_at: { type: "date" },
            withdrawn_at: { type: "date" },
            withdrawn: { type: "boolean" },
            reviewed: { type: "boolean" },
            ghsa_id: { type: "keyword" },
            cve_id: { type: "keyword" },
            severity: { type: "keyword" },
            ecosystem: { type: "keyword" },
            affects: { type: "keyword" },
            cwe_ids: { type: "integer" },
            cvss_v3_score: { type: "float" },
            cvss_v4_score: { type: "float" },
            credit_ids: { type: "integer" },
            classification: { type: "keyword" },
            epss_percentage: { type: "float" },
            epss_percentile: { type: "float" },
          }
        }
      }
    end

    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_vulnerabilities,
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
              min_gram: 1,
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
