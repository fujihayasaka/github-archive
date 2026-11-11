# typed: strict
# frozen_string_literal: true

module Issues
  class JobStatus < ::JobStatus
    include ::JobStatus::Context

    ID_PREFIX = "ijs"
    CACHE_KEY_PREFIX = T.let("issues/#{::JobStatus::CACHE_KEY_PREFIX}", String)

    sig { returns(Integer) }
    attr_reader :repository_id

    sig { params(attributes: T::Hash[T.untyped, T.untyped]).void }
    def initialize(attributes = {})
      raise ArgumentError, "Cannot initialize without a repository_id" unless attributes[:repository_id]
      raise ArgumentError, "repository must be an Integer" unless attributes[:repository_id].is_a?(Integer)

      @repository_id = T.let(attributes[:repository_id], Integer)

      if attributes[:id]
        raise ArgumentError, "id must start with '#{ID_PREFIX}:'" unless attributes[:id].split(":").first == ID_PREFIX
        raise ArgumentError, "id must have the repository id as the second id part" unless attributes[:id].split(":").second == attributes[:repository_id].to_s
      else
        attributes[:id] = "#{ID_PREFIX}:#{repository_id}:#{SecureRandom.uuid}"
      end

      super(attributes)

      @store = T.let(self.class.store_for_repository_id(repository_id), T.nilable(GitHub::KV))
    end

    sig { returns(T::Array[T.untyped]) }
    def self.tracked_jobs
      [
        IssueTriageJob,
      ].freeze
    end

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      /^#{ID_PREFIX}:\d+:.+$/.match?(id)
    end

    sig { params(id: String, meta: T::Hash[Symbol, T.untyped]).returns(T.nilable(JobStatus)) }
    def self.find(id, meta: {})
      repository_id = repository_id_from_cache_key(id)
      raise ArgumentError, "Wrong id format" unless repository_id

      store = store_for_repository_id(repository_id)

      json = store.get(cache_key(id)).value!

      return nil unless json

      parsed_json = JSON.parse(json, { symbolize_names: true })
      parsed_json[:repository_id] = repository_id

      self.new(parsed_json)
    end

    sig { returns(String) }
    def cache_key
      self.class.send(:cache_key, id)
    end

    sig { params(repository_id: Integer).returns(GitHub::KV) }
    def self.store_for_repository_id(repository_id)
      Issues::KV.for_repository_id(repository_id)
    end

    # this store is not scoped per repository
    # so it can only be used for suboptimal reads
    sig { returns(GitHub::KV) }
    def self.readonly_global_store
      Issues::KV.store
    end

    # global, unscoped store for compatibility with other read methods from the partent class
    sig { returns(GitHub::KV) }
    def self.kv_store
      self.readonly_global_store
    end

    private

    sig { params(cache_key: String).returns(T.nilable(Integer)) }
    def self.repository_id_from_cache_key(cache_key)
      string_id = cache_key.split(":").find { |part| part.match(/^\d+$/) }
      return nil unless string_id

      string_id.to_i
    end
    private_class_method :repository_id_from_cache_key

    sig { params(id: String).returns(String) }
    def self.cache_key(id)
      # this should be handled in the parent class
      # but sorbet doesn't allow for dynamic constant references so we can't use `self::CACHE_KEY_PREFIX`
      "#{CACHE_KEY_PREFIX}#{id}"
    end
    private_class_method :cache_key
  end
end
