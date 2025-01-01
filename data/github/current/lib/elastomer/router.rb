# typed: true
# frozen_string_literal: true

require "forwardable"

require "elastomer/router/template_methods"

module Elastomer

  # The purpose of the Router class is to map documents to the appropriate
  # search cluster and index.
  class Router
    extend Forwardable
    include Singleton
    include TemplateMethods

    RETRYABLE_METHODS = %i[get head].freeze

    # Initializes the Router singleton.
    def initialize
      @clients = Hash.new do |h, cluster|
        cluster_config = ::Elastomer.config.clusters[cluster]
        raise UnknownCluster, "unknown ElasticSearch cluster #{cluster.inspect}" if cluster_config.nil?
        raise UnknownCluster, "invalid ElasticSearch cluster config #{cluster.inspect}" if cluster_config[:url].nil?

        opts = {
          read_timeout: ::Elastomer.config.read_timeout,
          open_timeout: ::Elastomer.config.open_timeout,
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

        stamp_name = self.class.stamp
        stamp_prefix = !stamp_name.nil? ? "#{stamp_name}_" : ""

        h[cluster] = ::ElastomerClient::Client.new(**opts) do |connection|
          service_name = "elasticsearch_#{stamp_prefix + cluster}"

          retry_options = {
            client_name: service_name,
            stats: ::GitHub.dogstats,
            max: 1,
            interval: 0.05,
            interval_randomness: 0.5,
            backoff_factor: 2,
            methods: RETRYABLE_METHODS,
            exceptions: Faraday::Request::Retry::DEFAULT_EXCEPTIONS + [Faraday::ConnectionFailed]
          }
          connection.use GitHub::FaradayMiddleware::Retries, retry_options

          connection.use GitHub::FaradayMiddleware::Resilient,
            name: service_name,
            options: self.class.resilient_properties do |env|
              cb_status = env[:resilient_circuit].properties.force_open ? "forced open" : "tripped"
              env.body = %Q({"error": "circuit breaker #{cb_status} in #{cluster} cluster"})
            end

          connection.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: service_name
        end
      end
      self.reset!
    end

    def_delegators :@index_map,
        :refresh, :readable, :primary, :each_index_config

    # Public: The map responsible for keeping track of which index is
    # located on which cluster. Query this map to find out which index should
    # be written to when writing data. Query this map to find out which index
    # is handling queries for reading data.
    attr_reader :index_map

    # Public: When set to true, if an unknown index name is given we will raise
    # an exception. Otherwise we return the 'default' cluster name for unkonwn
    # indices.
    attr_accessor :raise_on_unknown_index

    def self.resilient_properties
      {
        instrumenter: ActiveSupport::Notifications,
        force_closed: !GitHub.flipper[:elastomer_circuit_breaker_open].enabled?,
        error_threshold_percentage: 60,
        request_volume_threshold: 2,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 1,
        sleep_window_seconds: 1
      }
    end

    # Given an Index or logical index name, return the Array of all writable
    # indices. The Array will contains the settings Hash for each of the
    # writable indices.
    #
    # key   - The logical index name or an Index.
    # slice - The slice identifier as a String (default `nil`).
    #
    # Returns an Array of all the writable indices.
    def writable(key, slice = nil)
      ary = @index_map.writable(key, slice)

      if ary.empty?
        key = @index_map.to_key(key)
        index_class = ::Elastomer.env.lookup_index(key)
        return ary unless index_class.sliced? && slice

        mutex = GitHub::Redis::MutexGroup.new(key, slice, timeout: 60, wait: 30, sleep: 1)
        mutex.lock do
          ary = writable_templates(key).map do |template|
            begin
              fullname = Elastomer::SearchIndexManager.create_or_return_index_from_template \
                  template: template,
                  slice:    slice
              @index_map[fullname]
            rescue ElastomerClient::Client::Error => err
              Failbot.report(err, "gh.elasticsearch.template.name": template.fullname, "gh.elasticsearch.slice": slice)
            end
          end
          ary.compact!
        end
      end

      ary
    end

    # Public: Resets the router back to its original default state.
    def reset!(raise_on_unknown_index: true)
      @clients.clear
      @index_map = IndexMap.new
      self.raise_on_unknown_index = raise_on_unknown_index
      self
    end

    # Public: Retrieve a client for the given cluster.
    #
    # cluster - The cluster name as a String or Symbol.
    #
    # Returns a client configured for the given cluster, or the default cluster
    # if none is specified.
    def client(cluster = "default")
      if Rails.env.development?
        cluster = Elastomer.config.clusters.find { |_key, value| value[:url] == GitHub.elasticsearch_url }&.first
      end
      @clients[cluster.to_s]
    end

    # Public: Get a list of configured cluster names.
    #
    # Returns an Array of cluster names.
    def clusters
      ::Elastomer.config.clusters.keys
    end

    # Public: Get the list of cluster names for those clusters that are
    # available.
    #
    # Returns an Array of cluster names.
    def available_clusters
      clusters.reject { |name| !client(name).available? }
    end

    # Returns `true` if multiple clusters have been configured.
    def multiple_clusters?
      ::Elastomer.config.clusters.length > 1
    end

    # Public: Given an index name, this will return the name of the cluster
    # where that index can be found.
    #
    # If the `raise_on_unknown_index` setting is true then an exception will
    # be raised if an unknown index name is given. Otherwise we return the
    # `default` cluster name for all unknown indexes.
    #
    # name - The index name as a String or Symbol
    #
    # Returns the cluster name as a String.
    def cluster_for_index(name)
      default = clusters.first
      return default unless multiple_clusters?

      config = index_map[name] || primary(name)

      if config && config.cluster
        config.cluster

      elsif raise_on_unknown_index
        raise UnknownIndex, "unknown ElasticSearch index #{name.inspect}"

      else
        default
      end
    end

    # Public: Given an index name, this will return an ElastomerClient::Client
    # connectd to the cluster where the index can be found.
    #
    # name - The index name as a String or Symbol
    #
    # Returns an ElastomerClient::Client connection.
    def client_for_index(name)
      cluster = cluster_for_index(name)
      client(cluster)
    end

    # Public: Given a specific index name, fetch the config for that index
    # from the index map. If the index does not exist, then `nil` will be
    # returned.
    #
    # name - The name of the index to lookup
    #
    # Returns an IndexConfig or nil.
    def get_index_config(name)
      index_map[name]
    end
    alias :index_settings :get_index_config

    # Public: Add or update the index config in our configuration store. This
    # config information can be retrieved by index name using the
    # `get_index_config` method.
    #
    # Returns the Router.
    def update_index_config(config)
      index_map.update(config)
      self
    end

    # Public: Remove the index config for the named index from the configuration
    # store.
    #
    # name - The name of the index to remove
    #
    # Returns an IndexConfig or nil.
    def remove_index_config(name)
      index_map.remove(name)
    end

    # Is this index on a cluster that is running ES 8 or higher?
    #
    # cluster_name - Required, name of the cluster to which the index is assigned.
    #   Consumers must provide this argument when an index is first being created, because it cannot be inferred.
    #
    def cluster_running_version_8_plus?(cluster_name)
      begin
        client(cluster_name).version_support.es_version_8_plus?
      rescue Elastomer::UnknownCluster => error
        Failbot.report(error, "db.elasticsearch.cluster.name": cluster_name)
        GitHub.dogstats.count("elastomer.unknown_cluster", 1, { tags: ["cluster:" + cluster_name] })
        raise error
      end
    end

    def self.stamp
      return ENV["HEAVEN_DEPLOYED_ENV"] if GitHub.multi_tenant_enterprise?
    end
  end
end
