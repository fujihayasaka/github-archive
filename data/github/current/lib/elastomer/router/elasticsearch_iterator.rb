# typed: true
# frozen_string_literal: true

module Elastomer
  class Router

    class ElasticsearchIterator
      include Enumerable

      # Iterate over all the configured clusters and yield an IndexConfig instance
      # for each index in the cluster that contains index metadata.
      #
      # Returns a new ElasticsearchIterator instance.
      def self.each(&block)
        self.new.each(&block)
      end

      # Iterate over all the configured clusters and yield an IndexConfig instance
      # for each index in the cluster that contains index metadata. The value
      # returned by the `block` will be stored in an Array. The Array of mapped
      # values is returned.
      #
      # Returns an Array of mapped values.
      def self.map(&block)
        self.new.map(&block)
      end

      # Iterate over all the configured Elasticsearch clusters and yield a
      # `TemplateConfig` for each index template on each cluster.
      #
      # Returns a new ElasticsearchIterator instance.
      def self.each_template(&block)
        self.new.each_template(&block)
      end

      # This is a special setting we use solely for storing immutable index
      # metadata.
      INDEX_META = Elastomer::Index::INDEX_META

      # Retrieve an IndexConfig from the ElasticSearch index metadata mapping.
      # Because we do not have an record of which indices are stored in which
      # clusters, we have to iterate over all clusters and search for the
      # desired index by name. If the same name is used in multiple clusters,
      # then the first one found is returend.
      #
      # name - The name of the search index
      #
      # Returns the IndexConfig for the search index or `nil` if the named search
      # index could not be found in any ElasticSearch cluster.
      def get_config(name)
        each_index.find { |config| name == config.name }
      end

      # Itereate over all the configured clusters and yield an IndexConfig
      # instance for each index in the cluster that contains index metadata.
      #
      # Returns an Enumerator unless a block is given; otherwise returns this
      # elasticsearch iterator.
      def each_index
        return to_enum(:each_index) unless block_given?

        each_client do |client, cluster_name|
          client.cluster.indices.each do |name, hash|
            primary_name = logical_index_name(name)
            next if primary_name.nil?
            next unless hash["state"] == "open"

            metadata = extract_metadata(cluster_name, primary_name, name, hash)
            config = IndexConfig.new(primary_name, metadata)

            yield config
          end
        end

        self
      end
      alias :each :each_index

      # Iterate over all the configured Elasticsearch clusters and yield a
      # `TemplateConfig` for each index template on each cluster.
      #
      # Returns an Enumerator unless a block is given; otherwise returns this
      # elasticsearch iterator.
      def each_template
        return to_enum(:each_template) unless block_given?

        each_client do |client, cluster_name|
          response = client.get("/_template")
          templates = response.body

          templates.each do |template_name, template|
            next unless TemplateConfig.valid?(template_name)
            yield TemplateConfig.new \
                name:     template_name,
                cluster:  cluster_name,
                template: template
          end
        end

        self
      end

      # Internal: Little helper method that iterates over all the configured
      # Elasticsearch clusters and yields an ElastomerClient::Client instance and the
      # name of the cluster that the client is connected to
      #
      # Returns this elasticsearch iterator.
      def each_client
        router = Elastomer.router

        router.clusters.each do |cluster_name|
          client = router.client(cluster_name)
          next unless client.available?

          yield client, cluster_name
        end

        self
      end

      # Internal: Helper method for extracting the index metadata from the
      # information hash.
      #
      # cluster      - The cluster name as a String
      # primary_name - The primary index name as a String
      # name         - The index name as a String
      # hash         - The Hash containing the index information
      #
      # Returns the metadata Hash.
      def extract_metadata(cluster, primary_name, name, hash)
        # ES8-COMPATIBILITY: Replace this shim with the correct call when we upgrade to ES8
        metadata = Elastomer::UpgradeShims.read_index_metadata(hash)

        primary = (primary_name == name) || hash["aliases"].include?(primary_name)

        metadata["name"]    = name
        metadata["cluster"] = cluster
        metadata["primary"] = primary

        metadata
      end

      # Internal: Lookup the logcial (or primary) index name for the given index
      # name. If the name does not map to any known index then `nil` is returend.
      #
      # name - The index name as a String
      #
      # Returns the logical index name or `nil` if the name does not map to any
      # known index.
      def logical_index_name(name)
        Elastomer.env.lookup_index(name).logical_index_name
      rescue Elastomer::UnknownIndex
        nil
      end

    end
  end
end
