# typed: true
# frozen_string_literal: true

module Elastomer
  class Router

    # An TemplateConfig is used to track the state of a search index template -
    # mainly wheither or not the template is configured as a primary template.
    class TemplateConfig

      # Is the given `template_name` valid in the current environment. This
      # allows us to distinguish between between test templates and development
      # templates.
      def self.valid?(template_name)
        index_name = template_name.sub(/_template\z/, "")
        index_class = ::Elastomer.env.lookup_index(index_name)
        index_class.slicer.fullname = index_name
        index_class.sliced?
      rescue ::Elastomer::UnknownIndex, ArgumentError
        false
      end

      attr_accessor :name
      attr_accessor :cluster
      attr_accessor :primary

      alias :primary? :primary

      # Create a new template config instance. All the mappings and settings for
      # the template will be read from the Index class associated with the
      # template `name`.
      #
      # name     - the name of the template as a String
      # cluster  - the name of the search cluster where the template exists
      # template - the template Hash read from the search cluster
      #
      def initialize(name:, cluster: "default", template: nil)
        @name    = name
        @cluster = cluster

        configure_from_template(template)
      end

      # Returns the SHA1 hex version string for this template config.
      def version
        return @version if defined? @version
        @version = ::Elastomer::SearchIndexManager.version \
            mappings:   index_class.mappings(cluster),
            settings:   index_class.settings(cluster)
      end

      # Returns true if the index template exists on the search cluster.
      def exists?
        response = client.head "/_template/#{name}"
        response.success?
      end
      alias :exist? :exists?

      # Returns a Slicer instance configured with the the name of this index
      # template.
      def slicer
        @slicer ||= begin
          s = index_class.slicer
          s.fullname = name.sub(/_template\z/, "")
          s
        end
      end

      # Returns the template version as an Integer. If there is not a template
      # version, then zero 0 is returned.
      def template_version
        slicer.index_version.to_i
      end

      # Internal: Returns the Elastomer index class for this template config.
      def index_class
        @index_class ||= begin
          index_name = name.sub(/_template\z/, "")
          ::Elastomer.env.lookup_index(index_name)
        end
      end

      # Internal: Returns the ElastomerClient::Client connected to the desired search
      # cluster.
      def client
        ::Elastomer.router.client(cluster)
      end

      # Internal: Returns the ElastomerClient::Client::Template instance configured
      # with the index tmplate `name`.
      def template
        client.template(name)
      end

      # Internal: Returns the primary alias name for the index class associated
      # with this index template.
      def primary_alias
        slicer.index_alias
      end

      # Internal: Configure this TemplateConfig from the given template Hash. If
      # you pass in a `nil` template then we try to get the template Hash from
      # the Elasticsearch cluster.
      #
      # hash - the template Hash as read from the Elasticsearch cluster
      #
      # Returns this TemplateConfig instance
      def configure_from_template(hash)
        if !hash.is_a? Hash
          hash = get_template
          return if hash.nil?
        end

        aliases = hash.dig("aliases")
        @primary = (aliases && aliases.keys.include?(primary_alias)) ? true : false

        # ES8-COMPATIBILITY: Replace this shim with the correct call when we upgrade to ES8
        metadata = Elastomer::UpgradeShims.read_index_metadata(hash)
        @version = metadata["version"]

        self
      end

      # Internal: Get the template from the Elasticsearch cluster.
      #
      # Returns the template Hash or nil
      def get_template
        hash = template.get
        hash[name]
      end
    end
  end
end
