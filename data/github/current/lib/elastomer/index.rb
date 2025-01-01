# typed: true
# frozen_string_literal: true

require "forwardable"

module Elastomer
  # The Index class understands data Adapter objects. Along with providing
  # access to the ElastomerClient::Client methods, it provides the `store` and
  # `remove` methods that work with the adapters to extract documents from
  # various data sources and store those documents in ElasticSearch.
  class Index
    extend Forwardable

    # This is a special mapping type we use solely for storing metadata about
    # the search index. This is the least horrible of all the hacks.
    INDEX_META = "index-meta".freeze

    # Sub-classes will override this method to provide index metadata.
    def self.metadata() nil; end

    # Sub-classes will override this method to provide settings.
    def self.settings_hook() nil; end

    # ES8-COMPATIBILITY: Transform settings if the cluster is ES8
    def self.settings(cluster_name)
      if Elastomer.router.cluster_running_version_8_plus?(cluster_name)
        return transform_settings_for_es8(settings_hook)
      end
      settings_hook
    end

    # Sub-classes will override this method to provide mappings.
    def self.mappings_hook() nil; end

    def self.mappings(cluster_name)
      if Elastomer.router.cluster_running_version_8_plus?(cluster_name)
        return transform_mapping_for_es_8(mappings_hook)
      end
      mappings_hook
    end

    def self.transform_mapping_for_es_8(mappings)
      return if mappings.nil?
      # Remove top-level mapping type from hash
      mappings = mappings.first.second

      # Remove _all hash from mapping
      mappings = mappings.except(:_all)

      # Change ES field type in dynamic templates from string to keyword
      if mappings.has_key?(:dynamic_templates)
        mappings[:dynamic_templates].each do |template|
          config = template.first[1]
          if config.dig(:mapping, :type) == "string" && config.dig(:mapping, :index) == "not_analyzed"
            config[:mapping][:type] = "keyword"
            config[:mapping].delete(:index)
          end
        end
      end

      mappings
    end

    # Returns an instance of the search index configured with the name and
    # cluster settings for the primary search index.
    def self.primary
      settings = ::Elastomer.router.primary(self)
      self.new(settings.name, settings.cluster) if settings
    end

    def self.transform_settings_for_es8(settings)
      return if settings.nil?
      # replace edgeNGram and nGram with edge_ngram and ngram, respectively
      settings = settings.deep_transform_values do |value|
        if value == "edgeNGram"
          "edge_ngram"
        elsif value == "nGram"
          "ngram"
        else
          value
        end
      end

      # remove index.mapper.dynamic from index settings
      if !settings.dig(:index, :mapper, :dynamic).nil?
        settings[:index][:mapper].delete(:dynamic)
      end

      # Related to https://github.com/github/repos/issues/6590
      # Add index.refresh_interval to index settings
      if settings[:index][:refresh_interval].nil?
        settings[:index][:refresh_interval] = "1s"
      end

      # Related to https://github.com/github/repos/issues/6582
      # Set number_of_routing_shards to number_of_shards
      settings[:index][:number_of_routing_shards] = settings[:index][:number_of_shards]

      # Increase max_terms_count since default terms count in ES8 is 65536,
      # which is too low for some searches (ex. searches based on repo_id)
      settings[:index][:max_terms_count] = 1000000

      settings
    end

    # Create a new Index that will search and store documents in the
    # specific ElasticSearch index.
    #
    # name    - The index name as a String or Symbol
    # cluster - The cluster name as a String or Symbol
    #
    def initialize(name = nil, cluster = nil)
      name = GitHub.get_search_index_override.presence || name.presence || self.class.index_name
      cluster = ::Elastomer.router.cluster_for_index(name) if cluster.nil?

      @cluster_name = cluster
      @client = ::Elastomer.router.client(@cluster_name)
      @index = @client.index(name)
      @docs = @index.docs
      @template = @client.template(name)
      @cluster = @client.cluster
      @bulk_request_size = 512.kilobytes
    rescue ElastomerClient::Client::ServerError => error
      @server_error = error
    end

    def_delegators :@index,
        :name, :exists?, :put_mapping, :mapping, :settings, :update_settings,
        :open, :close, :analyze, :bulk, :scan, :scroll, :refresh

    # ElastomerClient::Client instance
    attr_reader :client

    # API methods for working with the ES index.
    attr_reader :index

    # API methods for working with the ES template.
    attr_reader :template

    # API methods for working with the ES cluster.
    attr_reader :cluster

    # The name of the cluster where this index resides
    attr_reader :cluster_name

    # The default bulk request size for this index
    attr_reader :bulk_request_size

    # If index docs are unavailable, raise a ServerError
    def docs
      raise @server_error if @server_error

      @docs
    end

    # Returns the Time when the index was created.
    #
    # Raises ElastomerClient::Client::RequestError if the index does not exist.
    def creation_date
      return @creation_date if defined? @creation_date
      @creation_date = nil

      settings = @index.get_settings.values.first
      epoch_in_millis = settings["settings"]["index"]["creation_date"]
      return if epoch_in_millis.nil?

      epoch = Integer(epoch_in_millis) / 1000.0
      @creation_date = Time.at(epoch)
    end

    # Add an alias to this index.
    #
    # alias_name - The alias name as a String
    #
    # Returns the response body as a Hash.
    def add_alias(alias_name)
      @cluster.update_aliases add: { index: @index.name, alias: alias_name }
    end

    # Remove an alias from this index.
    #
    # alias_name - The alias name as a String
    #
    # Returns the response body as a Hash.
    def remove_alias(alias_name)
      @cluster.update_aliases remove: { index: @index.name, alias: alias_name }
    end

    # Returns the list of all aliases (an Array of Strings) associated with
    # this index.
    def get_aliases
      h = @index.get_aliases[@index.name]
      return [] unless h.key? "aliases"
      h["aliases"].keys
    end

    # Get the index configuration for this index.
    #
    # Returns an IndexConfig instance.
    def get_config
      config = Elastomer.router.get_index_config(name)

      if config.nil?
        metadata = get_metadata || {}
        config = Elastomer::Router::IndexConfig.new \
          name: name,
          cluster: cluster_name,
          version: metadata["version"]
      end

      config
    end

    # Update the index configuration for this index.
    #
    # hash - The Hash of values to update.
    #
    # Returns an IndexConfig instance.
    def update_config(hash)
      config = get_config
      config.update!(hash)
      Elastomer.router.update_index_config(config)
      config
    end

    # Fetch the metadata hash from the search index mappings. This will make a
    # call to the search cluster for this information.
    #
    # Returns the metadata Hash.
    def get_metadata
      Elastomer::Index.get_metadata @index
    end

    # Returns the SHA1 version string of the index stored in the ES settings
    # for the index. `nil` is returned if the index does not exist or has no
    # version string.
    def version
      return unless index.exists?

      version = get_metadata["version"]
      version.freeze unless version.nil?
    end

    # Create the index on the ElasticSearch cluster. If the class method
    # `mappings` exists it will be called and the returned value will be used
    # as the document type mappings for the index. Likewise, if the class
    # method `settings` exists it will be called and the returned value will
    # be used for the index settings during creation.
    #
    # opts - The options Hash
    #        :mappings - the Hash containing the document type mappings
    #        :settings - the Hash containing the index settings
    #        :metadata - the Hash containing index metadata (version, etc.)
    #
    # Returns the create operation result Hash from the ElasticSearch cluster.
    def create(opts = {})
      SearchIndexManager.create_index \
          name:        self.name,
          cluster:     self.cluster_name,
          index_class: self.class,
          mappings: opts[:mappings],
          settings: opts[:settings],
          metadata: opts[:metadata]
    end

    # Delete this index from the ElasticSearch cluster.
    #
    # Returns the delete operation result Hash from the ElasticSearch cluster.
    def delete(options = {})
      SearchIndexManager.delete_index \
          name:        self.name,
          cluster:     self.cluster_name,
          index_class: self.class
    end

    # Determines if the index has support for updating its mapping. Currently, only ES8 clusters support mapping
    # updates. Indexes that want to opt-out from allowing mapping updates can do so by returning false from this
    # method.
    sig { returns(T::Boolean) }
    def update_mapping_supported?
      # Only allow mapping updates to indices running on ES8 clusters to guarantee there is only one document type.
      Elastomer.router.cluster_running_version_8_plus?(cluster_name)
    end

    # Determines if the index has a mapping update that can be safely applied to the index.
    #
    # A valid mapping update consists of adding fields to an ES8 index that are not already present in the index. All
    # other mapping modifications or field removals are not supported.
    def update_mapping_valid?
      update_mapping_supported? &&
        mapping_diff.added.any? && # Must have at least one field being added
        mapping_diff.changed.empty? && # Must have no fields being changed
        mapping_diff.removed.empty? # Must have no fields being removed
    end

    # Returns a mapping diff object that represents the difference between the current mapping in the index and the
    # mapping as it would be in the code.
    #
    # The diff will contain a list of fields that would be added, changed, and removed from the index.
    #
    # The diff is only calculated once and is memoized for subsequent calls.
    sig { returns(Elastomer::Mappings::Diff) }
    def mapping_diff
      return @mapping_diff if defined?(@mapping_diff)

      unless update_mapping_supported?
        raise Elastomer::Mappings::UpdatesNotSupportedError.new(name)
      end

      # Mapping dictionary is different shape when fetching from Elasticsearch
      old_mapping = self.class.transform_mapping_for_es_8(index.get_mapping)["mappings"]
      # Generate the mapping as it would be in the code
      generated_mapping = SearchIndexManager.generate_mapping(
        cluster: cluster_name,
        index_class: self.class,
      )

      @mapping_diff = Elastomer::Mappings::Diff.new(old_mapping:, new_mapping: generated_mapping.mapping)
    end

    # Update the index mapping to match the current mapping for the index class.
    #
    # Returns the update operation result Hash from the ElasticSearch cluster.
    sig { returns(T::Boolean) }
    def update_mapping
      SearchIndexManager.update_index_mapping \
          name:        self.name,
          cluster:     self.cluster_name,
          index_class: self.class
    end

    # Perform a search request using the `query` document and the `params` hash.
    #
    # query  - The query Hash or JSON String
    # params - The request params Hash
    #          :type    - A single type String or an Array of type Strings
    #          :routing - A single routing String or an Array of routing Strings
    #          :search_type - The type of search to perform
    #
    # See the ElasticSearch documentation
    # (https://www.elastic.co/guide/en/elasticsearch/reference/master/search-search.html#search-type)
    # for an explanation of the search type.
    #
    # Returns a Hash containing the search results.
    # Raises an ElastomerClient::Client::Error upon failure.
    def search(query, params = {})
      GitHub.tracer.in_span("elastomer query", attributes: { "db.elasticsearch.path_parts.index" => self.name, "db.elasticsearch.cluster.name" => self.cluster_name }, kind: :internal) do |_span|
        params = params.merge(track_total_hits: true) if @index.client.version_support.es_version_8_plus?
        docs.search(query, params)
      end
    rescue ::ElastomerClient::Client::Error => boom
      # NOTE: Failbot does not like large exception messages and will not forward them
      boom.message.slice!(1024..-1)
      raise boom
    end
    alias :query :search

    # Count the number of documents in the search index that match the given
    # query.
    #
    # query  - The query Hash or JSON String.
    # params - The request params Hash.
    #          :type    - A single type String or an Array of type Strings
    #          :routing - A single routing String or an Array of routing Strings
    #
    # Returns the number of matching documents.
    # Raises a ElastomerClient::Client::Error upon failure.
    def count(query, params = {})
      hash = docs.count(query, params)
      hash["count"].to_i
    rescue ::ElastomerClient::Client::Error => boom
      # NOTE: Failbot does not like large exception messages and will not forward them
      boom.message.slice!(1024..-1)
      raise boom
    end
    alias :count_query :count

    # Count the number of documents in the search index that match the given
    # query. Uses the #search method in order to pass a timeout to Elasticsearch.
    #
    # query  - The query Hash or JSON String.
    # params - The request params Hash.
    #          :type    - A single type String or an Array of type Strings
    #          :routing - A single routing String or an Array of routing Strings
    #
    # Returns a Hash containing the search results.
    # Raises a ElastomerClient::Client::Error upon failure.
    def count_with_timeout(query, params = {})
      params = params.merge(track_total_hits: true) if @index.client.version_support.es_version_8_plus?
      docs.search(query, params.merge(size: 0))
    rescue ::ElastomerClient::Client::Error => boom
      # NOTE: Failbot does not like large exception messages and will not forward them
      boom.message.slice!(1024..-1)
      raise boom
    end

    # Given a data adapter object, this method will generate a document hash
    # from the adapter and store it in the search index. If the adapter
    # supports the `each` method, then multiple documents will be generated
    # and stored via bulk indexing.
    #
    # adapter - An Adapter instance
    # params  - Parameters Hash
    #
    # Returns the response body as a Hash.
    def store(adapter, params = {})
      adapter.index = self
      params = adapter.params.merge(params)

      if adapter.respond_to?(:each)
        # initiate a bulk transaction
        response = @index.bulk(request_size: bulk_request_size) do |bulk|
          start = Time.now
          adapter.each do |action, document|
            begin
              params = self.class.separate_document_and_params(document, cluster_running_version_8_plus: index_running_version_8_plus?)
              case action
              when :index, "index", :store, "store"
                start = fetch_timing(name, adapter.document_type, start)
                bulk.index document, params
              when :delete, "delete", :remove, "remove"
                bulk.delete params
              end
            rescue ElastomerClient::Client::Error => err
              Failbot.report err,
                "gh.elasticsearch.action": action,
                "db.elasticsearch.path_parts.index": name,
                "gh.elasticsearch.document.type": adapter.document_type,
                "gh.elasticsearch.document.id": adapter.document_id,
                "db.elasticsearch.cluster.name": @cluster_name
            end
          end
        end

        count_bulk_indexing_errors(response)
        response
      else
        start = Time.now
        doc = adapter.to_hash
        return if doc.nil?

        fetch_timing(name, adapter.document_type, start)
        docs.index(doc.dup, params)
      end
    end

    # Internal: Record timing statistics for how long it took to fetch a
    # document from the original data source.
    #
    # index - The name of the index
    # type  - The name of the document type
    # start - The start Time of the fetch process
    #
    # Returns a new start Time
    sig { params(index: String, type: String, start: Time).returns(Time) }
    def fetch_timing(index, type, start)
      GitHub.dogstats.timing("search.fetch", ((Time.now - start) * 1000).round, tags: %W[index:#{index} type:#{type} cluster:#{cluster_name}])
      Time.now
    end

    # Internal: Record failure metrics for a bulk indexing response if it has
    # errors.
    #
    # response - the bulk response from Elasticsearch (may be nil if response
    #            fails entirely)
    def count_bulk_indexing_errors(response)
      if response.present? && response.fetch("errors")
        items = response.fetch("items")
        failures = items.count { |item| !(200..299).cover?(item.values.first.fetch("status")) }
        GitHub.dogstats.count("rpc.elasticsearch.error", failures, tags: %W[rpc_operation:bulk index:#{index.name} cluster:#{cluster_name}])
      end
    end

    def self.separate_document_and_params(document, cluster_running_version_8_plus: false)
      params = {}

      if cluster_running_version_8_plus
        document.delete(:_type)
        params[:routing] = document.delete(:_routing)
      else
        params[:_type] = document.delete(:_type)
        params[:_routing] = document.delete(:_routing)
      end

      params[:_id] = document.delete(:_id)

      params
    end

    def index_running_version_8_plus?
      Elastomer.router.cluster_running_version_8_plus?(@cluster_name)
    end

    # Remove documents from the search index based on the `document_type` and
    # `id` from the adapter. If the adapter has a `delete_query` method, then
    # it will be used to remove multiple documents from the search index.
    #
    # adapter - An Adapter instance
    #
    # Returns the response body as a Hash.
    def remove(adapter)
      adapter.index = self

      if adapter.respond_to? :delete_query
        query, opts = adapter.delete_query
        opts[:type] = adapter.document_type unless opts.key? :type

        delete_by_query(query, opts)
      else
        params = {
          type: adapter.document_type,
          id:   adapter.document_id,
        }
        params[:routing] = adapter.document_routing if adapter.document_routing
        docs.delete(params)
      end
    end

    # Delete documents from this index based on a query. This method supports
    # both the "request body" query and the "URI request" query.
    #
    # query - The query body as a Hash
    # opts  - Options Hash
    #
    # Examples
    #
    #   # request body query
    #   delete_by_query({:query => {:match_all => {}}}, :type => 'tweet')
    #
    #   # same thing but using the URI request method
    #   delete_by_query(:q => '*:*', :type => 'tweet')
    #
    # Returns the response body as a hash
    def delete_by_query(query, opts = nil)
      if opts.nil? && query.key?(:q)
        opts, query = query, nil
      end

      if query && !query.key?(:query)
        query = { query: query }
      end

      docs.delete_by_query(query, opts)
    end

    # Public: The template identifier for creating and deleting the template.
    # Can be overridden in subclasses.
    #
    # Returns String.
    def template_id
      name
    end

    # Internal: Builds the request body for updating the index template with the
    # index's settings and mappings.
    #
    # Returns Hash.
    def template_data
      data = {
        settings: self.class.settings(cluster_name),
        mappings: self.class.mappings(cluster_name),
      }

      if index.index_running_version_8_plus?
        data[:index_patterns] = "#{template_id}-*"
      else
        data[:template] = "#{template_id}-*"
      end

      data
    end

    # Internal: Fetch the metadata hash from the search index mappings. This
    # will make a call to the search cluster for this information.
    #
    # index - ElastomerClient::Client::Index instance (or anything that provides a
    #         `mapping` method).
    #
    # Returns the metadata Hash.
    def self.get_metadata(index)
      # Throw away the index name wrapper via first.second, since names may or may not contain version (e.g. "repos-1" or "repos")
      hash = index.mapping(type: INDEX_META)&.first&.second

      # ES8-COMPATIBILITY: Replace this shim with the correct call when we upgrade to ES8
      Elastomer::UpgradeShims.read_index_metadata(hash)
    rescue ElastomerClient::Client::IndexNotFoundError
      {}
    end

    def self.write_index_metadata(mappings, metadata, cluster)
      Elastomer::UpgradeShims.write_index_metadata(mappings, metadata, cluster_running_version_8_plus: Elastomer.router.cluster_running_version_8_plus?(cluster))
    end

    # Default name for the current search index. This is generated from the
    # index class name and the current Rails environment.
    #
    # Examples
    #
    #   Elastomer::Indexes::Issues.index_name
    #   #=> 'issues-test'
    #   # Rails.env == 'test'
    #
    #   Elastomer::Indexes::CodeSearch.index_name
    #   #=> 'code-search'
    #   # Rails.env == 'production'
    #
    def self.index_name
      slicer.index
    end

    # The logical index name independent of the test environment settings.
    #
    # Examples
    #
    #   Elastomer::Indexes::Issues.logical_index_name
    #   #=> 'issues-test'
    #   # Rails.env == 'test'
    #
    #   Elastomer::Indexes::CodeSearch.logical_index_name
    #   #=> 'code-search'
    #   # Rails.env == 'production'
    #
    def self.logical_index_name
      slicer.index
    end

    # Internal: Helper method that will validate a specific index name against
    # this index. This check can be used to ensure that we don't perform
    # indexing operations against the wrong index.
    #
    # name  - The index name to validate
    #
    # Returns `true` if the index name is valid for this index
    def self.valid_index_name?(name)
      s = slicer
      s.fullname = name
      logical_index_name == s.index
    rescue ArgumentError
      false
    end

    # Internal: Returns the Slicer instance used to provide name analysis and
    # generation for this particular Index class. We use a method here so that
    # subclasses of Index can provide their own Slicer inmplementations.
    #
    # Returns a Slicer instance with the `index` configured for this Index class.
    def self.slicer
      Slicer.new(index: self)
    end

    # Public: Returns `true` if this index is sliced into smaller range or
    # date-based indices. The audit log is a good example of a date-based,
    # sliced index.
    def self.sliced?
      false
    end

    # Public: Constructs a slice name based on the given value using the Slicer
    # configured for this Index class.
    def self.slice_from_value(value)
      return nil if value.nil?

      value = value.slice_value if value.is_a?(::Elastomer::Adapter)
      slicer.slice_from_value(value)
    end
  end
end
