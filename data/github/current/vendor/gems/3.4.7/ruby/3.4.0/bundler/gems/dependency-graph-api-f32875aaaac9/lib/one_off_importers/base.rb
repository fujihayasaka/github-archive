module OneOffImporters
  class << self
    def run!(registry, args)
      importer = case registry
        when :npm then OneOffImporters::Npm
        when :pypi then OneOffImporters::Pypi
        when :rubygems then OneOffImporters::Rubygems
        when :nuget then OneOffImporters::Nuget
        when :composer then OneOffImporters::Composer
        when :go then OneOffImporters::Go
        when :actions then OneOffImporters::Actions
        else nil
      end

      raise ArgumentError, "Unimplemented or Invalid Registry" unless importer

      importer.new(**args).run
    end

    # Hydro::ProtobufEncoder massages a hash corresponding to a
    # PackageRelease record before it is published to Hydro; see
    # https://github.com/github/hydro-schemas/blob/master/proto/hydro/schemas/github/dependencygraph/v0/package_release.proto.
    #
    # It converts certain fields from the JSON-friendly formats
    # produced by some subclasses into the format expected by Hydro
    # (e.g. string ->Time).
    #
    # TODO(adonovan): this is an implementation detail of the
    # subclass(es), and doesn't belong here. This class's interface
    # should be expressed in terms of published formats e.g. PackageRelease.
    # See https://github.com/github/dependency-graph-api/issues/1998#issuecomment-868839807
    def build_hash(release_attributes)
      release_attributes["package_version"] = release_attributes.delete("version")
      release_attributes["built_at"] = OneOffImporters.parse_time(release_attributes["built_at"]).to_i unless release_attributes["built_at"].nil?
      release_attributes["published_at"] = OneOffImporters.parse_time(release_attributes["published_at"]).to_i unless release_attributes["published_at"].nil?
      release_attributes["unpublished_at"] = OneOffImporters.parse_time(release_attributes["unpublished_at"]).to_i unless release_attributes["unpublished_at"].nil?
      release_attributes["dependencies"].map { |dependency|
        dependency["scope"] = dependency["scope"]&.to_sym || :runtime
      } unless release_attributes["dependencies"].nil?
      release_attributes.compact
    end

    # Helper method to turn strings into Time.
    def parse_time(time)
      begin
        Time.at(time) if time.present?
      rescue TypeError => e
        time.present? ? Time.parse(time) : ""
      end
    end
  end

  class Base
    attr_accessor :package_name, :package_version

    def initialize(package_name:, package_version: nil, package_release_sink: nil)
      @package_name = package_name
      @package_version = package_version
      @package_release_sink = package_release_sink
    end

    # Public: Build a PackageRelease object based off of raw input.
    # Returns Packages::PackageRelease
    # (Used by Sink Proxy.)
    def build_package_release(attributes)

      Packages::PackageRelease.new(
        package_manager: attributes["package_manager"]&.to_sym,
        package_name: attributes["package_name"],
        namespace: attributes["namespace"],
        version: attributes["version"],
        description: attributes["description"],
        authors: attributes["authors"],
        download_count: attributes["download_count"],
        external_id: attributes["external_id"],
        source_url: attributes["source_url"],
        home_url: attributes["home_url"],
        docs_url: attributes["docs_url"],
        published_at: parse_time(attributes["published_at"]),
        unpublished_at: parse_time(attributes["unpublished_at"]),
        built_at: parse_time(attributes["built_at"]),
        dependencies: Array(attributes["dependencies"]).map { |dependency|
          Packages::PackageRelease::Dependency.new(
            package_name: dependency["package_name"],
            requirements: dependency["requirements"],
            scope: dependency["scope"]&.to_sym || :runtime,
          )
        }
      )
    end

    # TODO(adonovan): make subclasses responsible for calling build_hash.
    #
    # TODO(adonovan): merge request and parse, as they are always
    # called in composition, even by tests.
    #
    # See https://github.com/github/dependency-graph-api/issues/1998#issuecomment-868839807

    # Method to be overridden by a child class.
    # Requests data from the corresponding service and returns a Hash to be passed to parse.
    def request
      raise NotImplementedError, "You need to override the parse method in your own class!"
    end

    # Accepts a a list of PackageRelease-shaped hashes from the
    # request method, applies build_hash to each, and returns them.
    # Method to be overridden by a child class.
    def parse(input)
      raise NotImplementedError, "You need to override the parse method in your own class!"
    end

    # Calls parse(request()), then publishes each returned
    # PackageRelease-shaped hash to the sink (after applying
    # build_hash). Returns the number of items.
    #
    # A subclass may override this method to replace its behavior.
    # TODO(adonovan): stop abusing implementation inheritance: make
    # run abstract and make subclasses call helper functions for the
    # current run behavior.
    # See https://github.com/github/dependency-graph-api/issues/1998#issuecomment-868839807
    def run
      package_source = request
      releases = parse(package_source)

      releases.each do |release_attributes|
        package_release_sink.publish(OneOffImporters.build_hash(release_attributes))
      end

      package_release_sink.flush

      releases.size
    end

    private

    def package_release_sink
      @package_release_sink ||= default_package_release_sink
    end

    def default_package_release_sink
      Ingest::PackageProcessor.new
    end
  end
end
