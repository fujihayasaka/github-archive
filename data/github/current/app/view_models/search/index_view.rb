# typed: true
# frozen_string_literal: true

module Search
  class IndexView

    attr_accessor :name
    attr_accessor :kind
    attr_accessor :cluster
    attr_accessor :version
    attr_accessor :primary

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

      opts = opts.to_h.symbolize_keys

      self.cluster    = opts.fetch(:cluster, "default")
      self.version    = opts.fetch(:version, nil)
      self.searchable = opts.fetch(:searchable, opts.fetch(:read, true))
      self.writable   = opts.fetch(:writable, opts.fetch(:write, true))
      self.primary    = opts.fetch(:primary, false)
    end

    def new_record?
      name.nil?
    end

    def persisted?
      !name.nil?
    end

    def up_to_date?
      index_version = Elastomer::SearchIndexManager.version \
          mappings:   index_class.mappings(cluster),
          settings:   index_class.settings(cluster)

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

    def metadata
      {
        "read"  => searchable,
        "write" => writable,
      }
    end

    def create
      index.create(metadata: metadata) unless index.exists?
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

    delegate :update_mapping, :update_mapping_supported?, :update_mapping_valid?, :mapping_diff, to: :index

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
    def reindex_job
      Elastomer::SearchIndexManager.create_reindex_job(index)
    end

    sig { returns(T.nilable(Elastomer::RepairJob)) }
    def repair_job
      Elastomer::SearchIndexManager.create_repair_job(name)
    end

    def document_count
      query = { query: { match_all: {} } }
      if index.respond_to?(:count_all)
        index.count_all(query)
      else
        index.count(query)
      end
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
