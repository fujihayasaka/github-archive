# typed: true
# frozen_string_literal: true

# XXX Work around a double loading issue under 1.8.7 development environments.
# The Elastomer lib is full of really bad hacks for loading things due to
# lib/elastomer.rb being on both under lib/ and also in its own gem. There's a
# defined?(Elastomer::Error) check in elastomer/client that triggers Rails
# autoloading if this module is not defined. See the following for more info:
#
# https://github.com/github/github/issues/11101
#
# The elastomer gem and the lib files under lib/elastomer* should be fixed to not
# do any of this weird load path stuff and this hack should be removed.
module Elastomer
end

require "elastomer_client/client"
require "elastomer_client/notifications"
require "elastomer_client/core_ext/time"  # for proper JSON formatting of Time objects

require "github/faraday_adapter/persistent_excon"

# Elastomer provides an interface for indexing documents into a search engine
# and, subsequently, searching those documents.
#
module Elastomer
  autoload :Adapters, "elastomer/adapters"
  autoload :Mappings, "elastomer/mappings"

  extend self
  include Kernel

  # Parent class for Elastomer errors.
  Error = Class.new StandardError

  # This error is raised when attempting to lookup an adapter that does not
  # exist in the Elastomer::Adapters namespace.
  UnknownAdapter = Class.new Error

  # This error is raised when attempting to lookup an Index that does not
  # exist in the Elastomer::Indexes namespace.
  UnknownIndex = Class.new Error

  # This error is raised when attempting to lookup an Cluster that does not
  # exist in the current router configuration.
  UnknownCluster = Class.new Error

  # This error is raised when attempting to add a model to the search index
  # that has been deleted from the database.
  ModelMissing = Class.new Error

  # Namespace for the various data adapters. Each adapter is responsible for
  # one type of document that will be indexed into ElasticSearch. The adapter
  # retrieves information from the database (or the data store of choice) and
  # collates the information into a format that can be indexed by
  # ElasticSearch.
  #
  # Adapters perform the 'extract' and 'transform' steps. The loading of the
  # data is performed by one of the Index instance found in the Indexes
  # namespace.
  #
  module Adapters; end

  # Namespace for the separate indexes maintained by the library. Each index
  # in ElasticSearch should have a representative class in this module. The
  # class defines the [mappings](https://www.elastic.co/guide/en/elasticsearch/reference/master/mapping.html)
  # for the stored documents and the [settings](https://www.elastic.co/guide/en/elasticsearch/reference/master/index-modules.html)
  # for the index itself.
  #
  module Indexes; end

  # Public: Perform setup related to the ElasticSearch index. Configuration
  # settings are copied from the `GitHub::Config` module into our
  # `Elastomer::Config` module.
  #
  # Returns nil.
  def setup(options = {})
    environment.postfix = options.fetch(:postfix, nil)

    config.set_defaults

    config.read_timeout = GitHub.es_read_timeout
    config.open_timeout = GitHub.es_open_timeout

    config.clusters(GitHub.es_clusters)

    # Indexes will not exist on Enterprise when the application first starts;
    # they will only be available after the initial migrations finish.
    router.reset!(raise_on_unknown_index: !GitHub.enterprise?)

    nil
  end

  # Return the Environment for Elastomer.
  def environment
    ::Elastomer::Environment
  end
  alias :env :environment

  # Return the Config for Elastomer.
  def config
    ::Elastomer::Config
  end

  # Public: Returns the Router singleton. The Router is used to map indices to
  # a cluster. It maintains all the Elastomer client connections.
  def router
    Router.instance
  end

  # Public: Retrieve a client for the given cluster.
  #
  # cluster - The cluster name as a String or Symbol
  #
  # Returns a client configured for the given cluster, or the default cluster
  # if none is specified.
  def client(cluster = :default)
    router.client cluster
  end

  # Public: Given an adapter object, add the document returned by the adapter
  # to the correct search index.
  #
  # adapter - The adapter instance to add to the search index
  # opts    - The options Hash
  #   :index   - the index name as a String
  #   :cluster - the cluster name as a String
  #
  # Returns the Hash response from the ElasticSearch server or `nil` if the
  # document could not be stored.
  #
  def add_to_search_index(adapter, opts = {})
    failbot_attributes = {}
    return if adapter.nil?

    index = T.let(nil, T.untyped)
    index_class = environment.lookup_index(adapter)
    name    = opts["index"]   || opts[:index]
    cluster = opts["cluster"] || opts[:cluster]

    if name
      index = index_class.new(name, cluster)
      index.store(adapter)
    else
      responses = []
      each_writable_index(index_class, adapter) do |config|
        # A cluster was passed in directly and we may have been given
        # configuration to an index on a cluster we don't want to write to
        # and need to ignore the operation.
        next if cluster.present? && config.cluster != cluster
        failbot_attributes["db.elasticsearch.cluster.name"] = config.cluster

        begin
          index = index_class.new(config.name, config.cluster)
          responses << index.store(adapter)
        rescue ElastomerClient::Client::RequestSizeError => err
          Failbot.push app: "github-user"
          Failbot.report(err, failbot_attributes)
          error = err.class.name&.demodulize.underscore
          GitHub.dogstats.count("rpc.elasticsearch.error", 1, tags: %W[rpc_operation:store index:#{config.name} error:#{error}])
        rescue ElastomerClient::Client::DocumentAlreadyExistsError => err
          # Audit Log entries can be retried and are expected to return
          # DocumentAlreadyExistsError if the document already exists in
          # Elasticsearch.
          if index_class == Elastomer::Indexes::AuditLog
            GitHub.dogstats.increment("audit.entry.duplicate", tags: ["destination:elasticsearch"])
          else
            error = err.class.name&.demodulize.underscore
            GitHub.dogstats.count("rpc.elasticsearch.error", 1, tags: %W[rpc_operation:store index:#{config.name} error:#{error}])
            Failbot.report(err, failbot_attributes)
          end
        rescue ElastomerClient::Client::Error => err
          error = err.class.name&.demodulize.underscore
          GitHub.dogstats.count("rpc.elasticsearch.error", 1, tags: %W[rpc_operation:store index:#{config.name} error:#{error}])
          # NOTE: some errors can be retried - timeouts and connection errors
          # are good examples of this. We raise these retryable errors here so
          # that the caller can choose what to do. Take a look at the
          # `jobs/add_to_search_index.rb` task to see an example of retrying.
          raise err if err.retry?

          Failbot.report(err, failbot_attributes)
        ensure
          adapter.reset!
        end
      end

      responses.compact!
      return if responses.empty?
      return responses.first if responses.length == 1
      responses
    end
  rescue ElastomerClient::Client::DocumentAlreadyExistsError => err
    # Audit Log entries can be retried and are expected to return
    # DocumentAlreadyExistsError if the document already exists in
    # Elasticsearch.
    if index_class == Elastomer::Indexes::AuditLog
      GitHub.dogstats.increment("audit.entry.duplicate", tags: ["destination:elasticsearch"])
    else
      Failbot.report(err, failbot_attributes)
    end
  rescue ElastomerClient::Client::Error => err
    raise err if err.retry?
    Failbot.report(err, failbot_attributes)
  rescue GitRPC::ObjectMissing, Elastomer::Adapters::PullRequest::MissingCommitInfo, Elastomer::ModelMissing => err
    raise err
  rescue StandardError => err # rubocop:todo Lint/GenericRescue
    Failbot.report(err.with_redacting!, failbot_attributes)
  end

  # Public: Given an adapter object, remove the document from the search
  # index.
  #
  # adapter - The adapter instance to remove from the search index
  # opts    - The options Hash
  #   :index   - the index name as a String
  #   :cluster - the cluster name as a String
  #
  # Returns the Hash response from the ElasticSearch server.
  #
  def remove_from_search_index(adapter, opts = {})
    failbot_attributes = {}
    return if adapter.nil?

    index = T.let(nil, T.untyped)
    index_class = environment.lookup_index(adapter)
    name    = opts["index"]   || opts[:index]
    cluster = opts["cluster"] || opts[:cluster]

    if name
      index = index_class.new(name, cluster)
      index.remove(adapter)
    else
      each_writable_index(index_class, adapter) do |config|
        # A cluster was passed in directly and we may have been given
        # configuration to an index on a cluster we don't want to write to
        # and need to ignore the operation.
        next if cluster.present? && config.cluster != cluster
        failbot_attributes["db.elasticsearch.cluster.name"] = config.cluster

        begin
          index = index_class.new(config.name, config.cluster)
          index.remove(adapter)
        ensure
          adapter.reset!
        end
      end
    end
  rescue ElastomerClient::Client::Error => err
    raise err if err.retry?
    Failbot.report(err, failbot_attributes)
  rescue StandardError => err # rubocop:todo Lint/GenericRescue
    Failbot.report(err.with_redacting!, failbot_attributes)
  end

  # Helper method used to iterate over all the writable indices for a given
  # index class.
  #
  # index_class - An Index class
  # slice       - The slice identifier as a String or Adapter (default `nil`).
  #
  # Returns the last response from the block.
  def each_writable_index(index_class, slice = nil)
    slice = index_class.slice_from_value(slice)

    router.writable(index_class, slice).each do |config|
      begin
        if index_class.valid_index_name?(config.name)
          yield config
        else
          raise Error, "Invalid index name #{config.name.inspect} for #{index_class.name}"
        end
      rescue Elastomer::ModelMissing => err
        raise err
      rescue ElastomerClient::Client::Error => err
        raise err if err.retry?
        Failbot.report(err, "db.elasticsearch.cluster.name": config.cluster)
      rescue GitRPC::ObjectMissing, Elastomer::Adapters::PullRequest::MissingCommitInfo => err
        raise err
      rescue StandardError => err # rubocop:todo Lint/GenericRescue
        Failbot.report(err.with_redacting!, "db.elasticsearch.cluster.name": config.cluster)
      end
    end
  end

  # Given a result from ES, return the index name
  # without the version number that the result came from.
  # ex: "pull-requests-23" => "pull-requests"
  def get_index_name_from_result(result)
    index = result["_index"]

    # Use regex to match an optional postfix and an optional - with 1 or more digits on the end
    index.sub(/(#{Elastomer.env.postfix})?(-\d+)?\z/, "")
  end

end  # Elastomer

require "elastomer/app"
require "elastomer/analyzers"
require "elastomer/config"
require "elastomer/environment"
require "elastomer/upgrade_shims"
require "elastomer/client/inference"
require "elastomer/interfaces/api"
require "elastomer/interfaces/mapping"
require "elastomer/interfaces/document"

require "elastomer/adapter"

require "elastomer/index"
require "elastomer/indexes/audit_log"
require "elastomer/indexes/azure_models"
require "elastomer/indexes/code_search"
require "elastomer/indexes/commits"
require "elastomer/indexes/discussions"
require "elastomer/indexes/enterprises"
require "elastomer/indexes/gists"
require "elastomer/indexes/issues"
require "elastomer/indexes/issues_semantic"
require "elastomer/indexes/labels"
require "elastomer/indexes/marketplace_listings"
require "elastomer/indexes/memex_project_items"
require "elastomer/indexes/registry_packages"
require "elastomer/indexes/project_cards"
require "elastomer/indexes/projects"
require "elastomer/indexes/pull_requests"
require "elastomer/indexes/repository_actions"
require "elastomer/indexes/repos"
require "elastomer/indexes/releases"
require "elastomer/indexes/showcases"
require "elastomer/indexes/team_discussions"
require "elastomer/indexes/topics"
require "elastomer/indexes/users"
require "elastomer/indexes/vulnerabilities"
require "elastomer/indexes/wikis"
require "elastomer/indexes/workflow_runs"

require "elastomer/environment"
require "elastomer/reindex"
require "elastomer/router"
require "elastomer/router/index_config"
require "elastomer/router/template_config"
require "elastomer/router/template_methods"
require "elastomer/router/index_map"
require "elastomer/router/elasticsearch_iterator"
require "elastomer/router/mysql_store"
require "elastomer/slicer"
require "elastomer/slicers/date_slicer"
require "elastomer/slicers/audit_log_date_slicer"
require "elastomer/search_index_manager"
