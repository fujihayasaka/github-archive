# typed: true
# frozen_string_literal: true

module Search
  class IndexView
    include GitHub::Memoizer

    attr_accessor :name
    attr_accessor :kind
    attr_accessor :cluster
    attr_accessor :version
    attr_accessor :primary
    attr_accessor :ingestion_optimized

    sig { returns(Integer) }
    attr_accessor :read_pct

    attr :searchable, :writable

    alias :id :name

    def initialize(opts = {})
      self.name = opts.fetch(:name, nil)
      self.kind = opts.fetch(:kind, nil)

      if name && !kind
        self.kind = Elastomer.env.lookup_index(name).logical_index_name
      elsif kind && !name
        self.name = next_available_index_name
      end

      if name
        config = Elastomer.router.get_index_config(name)
        opts = config.to_h.merge(opts) unless config.nil?
      end

      opts = opts.to_h.with_indifferent_access

      if FeatureFlag.vexi.enabled?("elasticsearch_reindex_improvement", default: false)
        index_class = Elastomer.env.lookup_index(self.name) if self.name
        index_instance = index_class.new(self.name, opts[:cluster]) if self.name

        ingestion_optimized = if opts.key?(:ingestion_optimized)
          opts[:ingestion_optimized]
        elsif name
          begin
            index_instance.is_ingestion_optimized_index?
          rescue ElastomerClient::Client::IndexNotFoundError,
            Elastomer::Error,
            ElastomerClient::Error,
            Faraday::ConnectionFailed,
            Faraday::TimeoutError,
            SocketError,
            SystemCallError
            opts.fetch(:ingestion_optimized, false)
          end
        else
          false
        end

        self.ingestion_optimized = ingestion_optimized
      end

      self.cluster    = opts.fetch(:cluster, "default")
      self.version    = opts.fetch(:version, nil)
      self.searchable = opts.fetch(:searchable, opts.fetch(:read, true))
      self.writable   = opts.fetch(:writable, opts.fetch(:write, true))
      self.primary    = opts.fetch(:primary, false)
      self.read_pct   = opts.fetch(:read_pct, 0)
    end

    def new_record?
      name.nil?
    end

    def persisted?
      !name.nil?
    end

    def up_to_date?
      if FeatureFlag.vexi.enabled?("elasticsearch_reindex_improvement", default: false)
        index_version = Elastomer::SearchIndexManager.version \
          mappings:   index_class.mappings(cluster),
          settings:   index_class.settings(cluster),
          ingestion_optimized_settings: ingestion_optimized ? index_class.default_ingestion_optimized_index_settings : {}
      else
        index_version = Elastomer::SearchIndexManager.version \
          mappings:   index_class.mappings(cluster),
          settings:   index_class.settings(cluster)
      end

      version == index_version
    end

    def cluster_different_than_primary?
      return false unless Elastomer.router.primary(name)
      Elastomer.router.primary(name).cluster != cluster
    end

    def searchable=(value)
      @searchable = (value && value != "0") ? true : false
    end

    def writable=(value)
      @writable = (value && value != "0") ? true : false
    end

    sig { returns(Integer) }
    def display_read_pct
      return read_pct unless primary

      index_map = Elastomer.router.index_map
      all_indexes = index_map.fetch(kind) || []

      # We only support setting read_pct on ONE candidate, but since this isn't
      # enforced at the DB level, we ensure that we don't any introduced inconsistencies
      candidate_total = all_indexes.sum do |config|
        config.primary? ? 0 : config.read_pct
      end

      100 - candidate_total
    end

    sig { returns(T::Array[Elastomer::Router::IndexConfig]) }
    def candidates
      index_map = Elastomer.router.index_map
      all_indexes = index_map.fetch(kind) || []

      all_indexes.select do |config|
        !config.primary? && config.read_pct && config.read_pct > 0
      end
    end

    sig { returns(T.nilable(Elastomer::Router::IndexConfig)) }
    def other_candidate
      return nil if primary
      candidates.find { |c| c.name != name }
    end

    sig { returns(T.nilable(Elastomer::Router::IndexConfig)) }
    def primary_index
      return nil if primary

      index_map = Elastomer.router.index_map
      all_indexes = index_map.fetch(kind) || []

      all_indexes.find(&:primary?)
    end

    def metadata
      {
        "read"  => searchable,  # Deprecated
        "write" => writable,
        "read_pct" => read_pct,
      }
    end

    def create
      if FeatureFlag.vexi.enabled?("elasticsearch_reindex_improvement", default: false)
        if self.ingestion_optimized
          index.create(metadata: metadata, ingestion_optimized: true)
        else
          index.create(metadata: metadata)
        end
      else
        index.create(metadata: metadata)
      end
      self
    end

    def update
      index.update_config(metadata) if index.exists?

      GitHub.dogstats.event \
        "Index updated: #{name.inspect}",
        "Index config for #{name.inspect} updated to #{metadata.inspect}",
        tags: %W[search:ops action:update]

      self
    end

    delegate :update_mapping, to: :index

    sig { returns(T::Boolean) }
    def update_mapping_supported?
      index.update_mapping_supported?
    rescue Elastomer::Error, ElastomerClient::Error
      false
    end

    sig { returns(T.nilable(Elastomer::Mappings::Diff)) }
    def mapping_diff
      return @safe_mapping_diff if defined?(@safe_mapping_diff)

      @safe_mapping_diff = index.mapping_diff
    rescue Elastomer::Error, ElastomerClient::Error
      @safe_mapping_diff = nil
    end

    sig { returns(T::Boolean) }
    def update_mapping_valid?
      return false unless update_mapping_supported?

      diff = mapping_diff
      return false if diff.nil?

      diff.added.any? && diff.changed.empty? && diff.removed.empty?
    end

    def destroy
      index.delete if index.exists? && !primary
      self
    end

    def make_primary
      Elastomer::SearchIndexManager.promote_index_to_primary(name: name)
      self
    end

    def update_version
      index_version = Elastomer::SearchIndexManager.version(
        mappings: index_class.mappings(cluster),
        settings: index_class.settings(cluster)
      )

      index.update_config({ version: index_version })
      @version = index_version
    end

    sig { returns(T.nilable(Elastomer::Reindex)) }
    memoize def reindex_job
      Elastomer::SearchIndexManager.create_reindex_job(index)
    end

    sig { returns(T.nilable(Elastomer::RepairJob)) }
    def repair_job
      Elastomer::SearchIndexManager.create_repair_job(name)
    end

    def optimize_for_serving
      settings_hook = index_class.settings(cluster).transform_keys(&:to_s)["index"]
      current_settings = index.index_settings.transform_keys(&:to_s)["index"]

      new_settings = settings_deep_diff(
        normalize_settings(settings_hook),
        normalize_settings(current_settings)
      )

      return if new_settings.empty?

      Elastomer::SearchIndexManager.update_index_settings(
        name: name,
        settings: new_settings,
        cluster: cluster,
        reopen: true
      )

      # Update the version digest to reflect the new settings
      update_version
    end

    # Internal: Normalize settings for comparison by expanding dotted keys into nested hashes,
    # stringifying all keys and values.
    sig { params(settings: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    def normalize_settings(settings)
      settings.each_with_object({}) do |(key, value), result|
        string_key = key.to_s
        if string_key.include?(".")
          parts = string_key.split(".")
          last_part = parts.pop
          nested = parts.inject(result) { |hash, part| hash[part] ||= {} }
          if value.is_a?(Hash)
            nested[last_part] = normalize_settings(value)
          else
            nested[last_part] = value.to_s
          end
        elsif value.is_a?(Hash)
          result[string_key] = normalize_settings(value)
        else
          result[string_key] = value.to_s
        end
      end
    end

    # Internal: Return only settings in `hash1` that are missing from `hash2` or have different values.
    sig { params(hash1: T.untyped, hash2: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    def settings_deep_diff(hash1, hash2)
      hash1.each_with_object({}) do |(key, value1), result|
        if hash2.key?(key)
          value2 = hash2[key]
          if value1.is_a?(Hash) && value2.is_a?(Hash)
            nested = settings_deep_diff(value1, value2)
            result[key] = nested unless nested.empty?
          elsif value1 != value2
            result[key] = value1
          end
        else
          result[key] = value1
        end
      end
    end
    private :normalize_settings, :settings_deep_diff

    sig { returns(T.nilable(Integer)) }
    def document_count
      query = { query: { match_all: {} } }
      if FeatureFlag.vexi.enabled?("elasticsearch-stafftools-improvement", default: false)
        index_instance = index
        if index_instance.is_a?(Elastomer::Indexes::MemexProjectItems)
          T.cast(index_instance, Elastomer::Indexes::MemexProjectItems).count_all(query)
        else
          index_instance.count(query)
        end
      elsif index.respond_to?(:count_all)
        index.count_all(query)
      else
        index.count(query)
      end
    rescue Elastomer::Error, ElastomerClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError, SocketError, SystemCallError
      nil
    end

    sig { returns(T::Boolean) }
    def index_is_green?
      index.index_health == "green"
    rescue Elastomer::Error, ElastomerClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError, SocketError, SystemCallError
      false
    end

    # We want to be able to truthfully display the candidate routing state
    # even if the current user doesn't have access to modify it, while we test these features,
    # so we gate this by two different flags.
    def candidate_routing_enabled?(user)
      FeatureFlag.vexi.enabled?(:elastomer_read_percent_enabled, default: false)
    end

    def modify_candidate_routing_enabled?(user)
      return false if GitHub.enterprise?
      candidate_routing_enabled?(user) && FeatureFlag.vexi.enabled?(:elastomer_sim_modify_read_percent_enabled, user, default: false)
    end

    # Internal:
    #
    def next_available_index_name
      Elastomer.router.index_map.next_available_index_name(kind)
    end

    # Internal:
    #
    def client
      Elastomer.client(cluster)
    end

    # Internal:
    #
    def index_class
      Elastomer.env.lookup_index(kind)
    end

    # Internal:
    #
    def index
      @index ||= index_class.new(name, cluster)
    end

    # Internal:
    #
    def aliases
      if index_class.respond_to? :aliases
        index_class.aliases
      else
        [kind]
      end
    end

    # Gotta have these two methods so this view model can be used in a form.
    def self.model_name
      ActiveModel::Name.new self
    end

    def model_name
      self.class.model_name
    end

    def to_key
      [name]
    end
  end
end
