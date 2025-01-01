# typed: true
# frozen_string_literal: true

module Elastomer
  class Router

    class IndexMap
      TTL   = 2.minutes.to_i

      attr_reader :store

      # Create a new IndexMap
      def initialize
        @store   = MysqlStore.new
        @expires = nil
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
        settings = fetch(key)
        return [] if settings.nil?

        settings.select { |config| config.writable? && config.slice == slice }
      end

      # Given an Index or logical index name, return the Array of all readable
      # indices. The Array will contains the settings Hash for each of the
      # readable indices.
      #
      # key   - The logical index name or an Index.
      # slice - The slice identifier as a String (default `nil`).
      #
      # Returns an Array of all the readable indices.
      def readable(key, slice = nil)
        settings = fetch(key)
        return [] if settings.nil?

        settings.select { |config| config.readable? && config.slice == slice }
      end

      # Given an Index or logical index name, return an Array of all primary
      # indices.
      #
      # key   - The logical index name or an Index.
      # slice - The slice identifier as a String (default `nil`).
      #
      # Returns the primary index settings Hash or nil.
      def primary(key, slice = nil)
        settings = fetch(key)
        return if settings.nil?

        if slice == "*"
          settings.select { |config| config.primary? && !config.slice.nil? }
        else
          settings.find { |config| config.primary? && config.slice == slice }
        end
      end

      # Given an Index or logical index name, return an Array of all primary
      # indices. The Array will contains the settings Hash for each of the
      # primary indices.
      #
      # key   - The logical index name or an Index.
      # slice - The slice identifier as a String (default `nil`).
      #
      # Returns an Array containing primary index Hashe(s) or an empty Array.
      def primaries(key, slice = nil)
        settings = fetch(key)
        return if settings.nil?
        settings.select { |config| config.primary? && config.slice == slice }
      end

      # Given a specific index name, return the settings for that index.
      # If the index does not exist, then `nil` will be returned.
      #
      # name - The specific index name to lookup
      #
      # Returns the index settings Hash or nil.
      def [](name)
        settings = fetch(name)
        return if settings.nil?

        settings.find { |config| config.name == name }
      end

      # Iterate over each available index and yield and IndexConfig instance. If
      # a block is not given, then an Enumerator is returned.
      #
      # Returns an Enumerator if no block is given; returns self otherwise
      def each_index_config
        return to_enum(:each_index_config) unless block_given?
        canonical_map.each_value do |ary|
          ary.each { |index_config| yield index_config }
        end
        self
      end

      # Lookup the index configs for all slices of an index. The index name and
      # version are required to select all the slices.
      #
      # name - The index name with version number
      #
      # Returns an Array of index settings.
      def all_index_slices(name)
        settings = fetch(name)
        return [] if settings.nil?

        slicer = Elastomer.env.lookup_slicer(name)
        slicer.fullname = name
        version = slicer.index_version
        version = version.to_i unless version.nil?

        settings.select { |config| config.index_version == version }
      end

      # This fantastic little method returns the next availabe index name.
      # Given a logical index name (or an Index class), this method will look
      # at all the indices of that type that exist across all the clusters and
      # return the next available name.
      #
      # So if we have an `issues-2` index and an `issues-5` index, the next
      # available name is `issues-6`. The index name is created by appending a
      # monotonically increasing number to the logical index name.
      #
      # key - The logical index name or an Index.
      #
      # Returns the next index name as a String.
      def next_available_index_name(key)
        slicer = Elastomer.env.lookup_slicer(key)
        settings = fetch(key)

        num =
          if settings
            ary = settings.map { |config| config.index_version }
            ary.compact.sort.last.to_i
          else
            0
          end

        slicer.slice = nil
        slicer.slice_version = nil
        slicer.index_version = num + 1

        slicer.fullname
      end

      # Returns the next available index slice name. Taking audit logs as an
      # example, if an index named "audit_log-2-2017-04-2" already exists then
      # this method will return "audit_log-2-2017-04-3" when the slice encoded
      # in the `name` includs the "2017-04" year/month string.
      #
      # Basically this finds the largest slice version number and bumps it by
      # one.
      #
      # name - String index name with slice information
      #
      # Returns the index name as a String
      def next_available_index_slice_name(name)
        slicer = Elastomer.env.lookup_slicer(name)
        slicer.fullname = name
        slice = slicer.slice
        return if slice.nil?

        settings = fetch(name)
        index_version = slicer.index_version
        index_version = index_version.to_i unless index_version.nil?

        num =
          if settings
            ary = settings.map do |config|
              next unless config.index_version == index_version && config.slice == slice
              config.slice_version
            end
            ary.compact.sort.last.to_i
          else
            0
          end

        if slicer.index_version || num > 0
          slicer.slice_version = num + 1
        end
        slicer.fullname
      end

      # Refresh the canonical map by reading the index settings from all
      # clusters.
      #
      # name - Currently ignored
      #
      # Returns this index map.
      def refresh(name = nil)
        canonical_map(true)

        self
      end

      # Iterate over all the indices found in the Elasticsearch clusters and
      # create an entry in the MySQL table for the index if one does not exist.
      # By default, any existing metadata settings found in the Elasticsearch
      # clusters will not be stored in the search index. That is, the `read` and
      # `write` attributes will be set to `false`. Use the `:override` setting
      # to change this behavior.
      #
      # :override - Defaults to `true`
      #
      # Returns this index map.
      def reconcile(override: true)
        needs_refresh = T.let(false, T::Boolean)
        map = canonical_map(true)

        ElasticsearchIterator.each do |config|
          next if GitHub.enterprise? && !GitHub.es_clusters.empty? && config.cluster != GitHub.primary_datacenter
          ary = map[to_key(config.name)]
          if ary.nil? || !ary.find { |m| m.name == config.name }
            if override
              config.read    = false
              config.write   = false
              config.primary = false
            end
            store.put_config(config)
            needs_refresh = true
          end
        end

        refresh if needs_refresh
        self
      end

      # Add or update a particular index in the canonical map.
      #
      # config - IndexConfig
      #
      # Returns this index map.
      def update(config)
        extract(config.name)
        store.put_config(config)
        insert(config)
        self
      end

      # Remove a particular index from the canonical map.
      #
      # name - The index name as a String.
      #
      # Returns the IndexConfig or `nil`.
      def remove(name)
        config = extract(name)
        store.delete_config(name)
        config
      end

      # Internal: This is the canonical mapping of logical index names to
      # their concerete implementations located in one or more search clusters.
      # Each logical index name is mapped to an array of index settings
      # Hashes. Each Hash defines the real index name, the cluster where it
      # lives, readability, and writability.
      #
      # Examples
      #
      #     canonical_map['test']
      #     #=> [{ :name    => 'test-1',
      #            :cluster => 'default',
      #            :version => 'SHA1 version string',
      #            :read    => true,
      #            :write   => true  }]
      #
      # force - Boolean flag used to force reloading index settings.
      #
      # Returns the index mappings Hash.
      def canonical_map(force = false)
        if defined?(@canonical) && !force
          return @canonical if @expires && Time.now < @expires
        end
        @expires = Time.now + TTL
        canonical = {}

        store.each do |config|
          key = to_key config.name
          ary = canonical[key] ||= []
          ary << config
        end

        @canonical = canonical
      end

      # Internal: Extract the config for a particular index from the
      # canonical map. The config is deleted from the canonical map with
      # the understanding that it will be modified and later inserted again.
      # The exception to this is when an index is being removed altogether.
      #
      # name - An index name (not a read alias)
      #
      # Returns an IndexConfig or nil.
      def extract(name)
        key = to_key(name)
        map = canonical_map(true)
        ary = map[key] ||= []

        rv = T.let(nil, T.untyped)
        ary.delete_if { |config| rv = config if name == config.name }
        rv
      end

      # Internal: Insert the index config into the canonical map. This
      # config should have been `extracted` from the canonical map first;
      # otherwise calling this method will result in duplicate entries.
      #
      # config - IndexConfig
      #
      # Retuns the config
      def insert(config)
        key = to_key(config.name)
        ary = canonical_map[key] ||= []
        ary << config
        config
      end

      # Internal: Convert key into a logical index name.
      #
      # key - an Index or a String
      #
      # Returns a String.
      def to_key(key)
        return key.logical_index_name if key.respond_to?(:logical_index_name)

        slicer = ::Elastomer::Slicer.new(postfix: nil)
        key = key.to_s
        begin
          slicer.fullname = key
        rescue ArgumentError
          slicer.index = key
        end
        slicer.index
      rescue ArgumentError
        key.sub(/-\d+(-\d+)*\Z/, "")
      end

      # Internal: Fetch the settings for the index with the given key.
      #
      # key - an Index or a String
      #
      # Returns an Array of index settings Hashes or nil.
      def fetch(key)
        key = to_key(key)
        canonical_map[key]
      end
    end

  end
end
