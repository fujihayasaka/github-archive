# typed: true
# frozen_string_literal: true

module Elastomer
  class Router

    # An IndexConfig is used to track the state of a search index - whether it
    # is readable and writable, whether it is the primary index, etc. The
    # IndexConfig is persisted by an external store such as the MysqlStore.
    class IndexConfig

      attr_accessor :name
      attr_accessor :cluster
      attr_accessor :version
      attr_accessor :read
      attr_accessor :write
      attr_accessor :primary

      alias :readable? :read
      alias :writable? :write
      alias :primary? :primary

      # Create a new IndexConfig from the given attributes. If the `primary_name`
      # is provided and it matches the index `name` then the `read`, `write`,
      # and `primary` attributes all default to `true`. Normally these three
      # attributes default to `false`. The values provided in the attributes
      # Hash always take precedence.
      #
      # primary_name - Primary index name as a String (optional)
      # attrs - Attributes Hash (required)
      #   :name    - index name as a String (required)
      #   :cluster - cluster name as a String (required)
      #   :version - index version String (optional)
      #   :read    - boolean (optional)
      #   :write   - boolean (optional)
      #   :primary - boolean (optional)
      #
      def initialize(*args)
        opts = args.extract_options!
        opts = opts.symbolize_keys
        primary_name = args.first

        self.name    = opts.fetch(:name)
        self.cluster = opts.fetch(:cluster)
        self.version = opts.fetch(:version, nil)

        self.primary = opts.fetch(:primary, (primary_name == name))
        self.read    = opts.fetch(:read,    primary)
        self.write   = opts.fetch(:write,   primary)
      end

      # Returns the Elastomer::Index instance described by this index config.
      def index
        index_class.new(self.name, self.cluster)
      end

      # Returns the Elastomer index class described by this index config.
      def index_class
        @index_class ||= Elastomer.env.lookup_index(self.name)
      end

      def exists?
        Elastomer.router.client(cluster).index(name).exists?
      end

      # Returns the index name slicer for this index config.
      def slicer
        return @slicer if defined? @slicer
        @slicer =
            begin
              index_class.slicer
            rescue Elastomer::UnknownIndex
              Elastomer::Slicer.new
            end
        @slicer.fullname = name
        @slicer
      end

      # Returns the index version as an Integer value or `nil` if there is no
      # version number.
      def index_version
        version = slicer.index_version
        version.nil? ? nil : version.to_i
      end

      # Returns the index slice name as a String or `nil` if this index config
      # does not reference an index slice.
      def slice
        slicer.slice
      end

      # Returns the index slice version as an Integer value or `nil` if this
      # index config does not reference an index slice.
      def slice_version
        version = slicer.slice_version
        version.nil? ? nil : version.to_i
      end

      # Compare the name of this IndexConfig with the name of the `other`
      # IndexConfig.
      def <=>(other)
        return nil unless other.is_a?(IndexConfig)

        self.name <=> other.name
      end

      # Return the list of alisas that should be applied to the index when it is
      # promoted to the primary role.
      #
      # Returns an Array of alias names.
      def aliases
        ary = [slicer.index_alias, slicer.slice_alias]
        if index_class.respond_to?(:aliases)
          ary.concat(index_class.aliases)
        end
        ary.compact!
        ary.uniq!
        ary
      end

      # Update multiple values in this IndexConfig by passing in a Hash containing
      # the key/value pairs to update.
      #
      # hash - The Hash containing the key/values to udpate
      #
      # Returns this IndexConfig.
      def update!(hash)
        hash = hash.symbolize_keys

        self.name    = hash[:name]    if hash.has_key?(:name)
        self.cluster = hash[:cluster] if hash.has_key?(:cluster)
        self.version = hash[:version] if hash.has_key?(:version)
        self.read    = hash[:read]    if hash.has_key?(:read)
        self.write   = hash[:write]   if hash.has_key?(:write)
        self.primary = hash[:primary] if hash.has_key?(:primary)

        self
      end

      # Convert this config object into a Hash representation.
      def to_h
        {
          name:    name,
          cluster: cluster,
          version: version,
          read:    read,
          write:   write,
          primary: primary,
        }
      end

      # Convert this config object into a JSON string representation.
      def to_json
        GitHub::JSON.dump(self.to_h)
      end

      # Test equality between this IndexConfig instance and the `other`
      # IndexConfig instance.
      #
      # Returns `true` if the two objects are equivalent.
      def ==(other)
        return true if self.equal?(other)

        if other.is_a?(IndexConfig)      \
        && self.name    == other.name    \
        && self.cluster == other.cluster \
        && self.version == other.version \
        && self.read    == other.read    \
        && self.write   == other.write   \
        && self.primary == other.primary
          true
        else
          false
        end
      end

    end
  end
end
