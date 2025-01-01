# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Elasticsearch
      include Kernel
      # For certain Enterprise configurations, Elasticsearch cluster configuration
      # is passed in via an environment variable as a JSON-encoded string.
      # The string needs to be parsed into a form that can be passed to GitHub.es_clusters
      def parse_es_clusters(raw_cluster_config: "")
        return {} if raw_cluster_config.empty?
        clusters = JSON.parse(raw_cluster_config)
        clusters.map { |k, v| [k, v.transform_keys(&:to_sym)] }.to_h
      rescue Yajl::ParseError
        raise ArgumentError, "Failed to parse value for es_clusters: #{raw_cluster_config}"
      end

      def set_search_index_override(index_name)
        Thread.current[:search_index_override] = index_name
      end

      def get_search_index_override
        Thread.current[:search_index_override]
      end
    end
  end

  extend Config::Elasticsearch
end
