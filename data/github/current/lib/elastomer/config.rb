# typed: true
# frozen_string_literal: true

module Elastomer

  #
  #
  module Config
    extend self

    # This is the read timeout (in seconds) that will be used for all
    # ElasticSearch network operations.
    attr_accessor :read_timeout

    # The connection open timeout (in seconds) that will be used for all
    # Elasticsearch connection attempts.
    attr_accessor :open_timeout

    #
    #
    def clusters(hash = nil)
      return @clusters if hash.nil?

      @clusters.merge! hash
      @clusters
    end

    #
    #
    def clusters=(hash)
      @clusters = hash
    end

    # Internal: Set all the configuration items to sane default values.
    #
    # force - Boolean flag to force resetting everything to the default values
    #
    # Returns this Config module.
    def set_defaults(force = false)
      return if defined?(@set_defaults) && !force
      @set_defaults = true

      self.read_timeout = 5
      self.open_timeout = 1

      self.clusters = {
        # NOTE: Leaving out :es_version key will cause Elastomer to fetch the version from Elasticsearch
        # NOTE: Leaving out the :compress_body key will cause Elastomer to not compress request bodies
        "default" => {
          url: GitHub.elasticsearch_url,
        },
      }

      self
    end

  end
end
