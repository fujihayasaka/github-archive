module Packages
  class PackageReleaseSerializer < ActiveJob::Serializers::ObjectSerializer
    OBJECT_SERIALIZER_KEY = "_aj_serialized"

    def klass
      PackageRelease
    end

    def serialize(release)
      hsh = release.to_h
      hsh[:dependencies] = hsh[:dependencies]&.map(&:to_h)
      super(hsh)
    end

    def deserialize(hash)
      hash.delete(OBJECT_SERIALIZER_KEY)
      hash.transform_keys!(&:to_sym)
      hash[:built_at] = Time.iso8601(hash[:built_at]) unless hash[:built_at].nil?
      hash[:published_at] = Time.iso8601(hash[:published_at]) unless hash[:published_at].nil?
      hash[:unpublished_at] = Time.iso8601(hash[:unpublished_at]) unless hash[:unpublished_at].nil?
      hash[:dependencies] = hash[:dependencies].map { |d| PackageRelease::Dependency.new(**d.transform_keys(&:to_sym)) }
      hash[:attributions] = Array(hash[:attributions])
      PackageRelease.new(**hash)
    end
  end

  ActiveJob::Serializers.add_serializers PackageReleaseSerializer

  class PackageRelease
    include ActiveModel::Validations

    validates :package_name, :version, presence: true

    validate :valid_package_manager

    # The Types::PackageManager package manager
    attr_reader :package_manager

    # The String package name
    attr_reader :package_name

    # The String semantic package version
    attr_reader :version

    # The String namespace if the the package is scoped to a namespace
    attr_reader :namespace

    # The String package description
    attr_reader :description

    # The String package author or authors
    attr_reader :authors

    # The Integer package download count
    attr_reader :download_count

    # The String third-party package host identifier for this package
    attr_reader :external_id

    # The String URL that hosts the package source code
    attr_reader :source_url

    # The String URL that hosts the package homepage
    attr_reader :home_url

    # The String URL that hosts the package documentation
    attr_reader :docs_url

    # The String value that, if populated, should be
    # considered an authoritative entry from the
    # package ecosystem's PMA that can safely override
    # previously recorded ClearlyDefined data
    attr_reader :license

    # The Time that the package version was published
    attr_reader :published_at

    # The Time that the package version was unpublished
    attr_reader :unpublished_at

    # The Time that the package version was built
    attr_reader :built_at

    attr_reader :clearly_defined_score

    attr_writer :dependencies

    attr_reader :attributions

    def initialize(package_manager:, package_name:, version:, namespace: nil,
                   description: nil, authors: nil, download_count: 0,
                   external_id: nil, source_url: nil, home_url: nil,
                   docs_url: nil, license: nil, published_at: nil,
                   unpublished_at: nil, built_at: nil,
                   clearly_defined_score: nil, dependencies: [],
                   attributions: [])
      @package_manager = package_manager
      @package_name = package_name
      @version = version
      @namespace = namespace
      @description = description
      @authors = authors
      @download_count = download_count.to_i
      @external_id = external_id
      @source_url = source_url
      @home_url = home_url
      @docs_url = docs_url
      @license = license.to_s
      @published_at = published_at
      @unpublished_at = unpublished_at
      @built_at = built_at
      @clearly_defined_score = clearly_defined_score
      @dependencies = dependencies
      @attributions = attributions
    end

    def package_manager # rubocop:disable Lint/DuplicateMethods
      Types::PackageManager.coerce(@package_manager) if @package_manager
    end

    def dependencies
      @dependencies.select(&:valid?)
    end

    def ==(other)
      return unless other.is_a?(PackageRelease)

      attributes == other.attributes
    end

    def to_h
      # Get rid of the "@"s in instance variables
      hsh = attributes.each_with_object({}) do |(k, v), hsh|
        key = k.to_s.gsub(/^@/, "").to_sym
        hsh[key] = v
      end
    end

    protected

    def attributes
      {
        package_manager: package_manager&.to_s,
        package_name: package_name,
        version: version,
        namespace: namespace,
        description: description,
        authors: authors,
        download_count: download_count,
        external_id: external_id,
        source_url: source_url,
        home_url: home_url,
        docs_url: docs_url,
        license: license,
        published_at: published_at&.to_time&.iso8601,
        unpublished_at: unpublished_at&.to_time&.iso8601,
        built_at: built_at&.to_time&.iso8601,
        dependencies: dependencies,
        attributions: attributions,
      }
    end

    private

    def valid_package_manager
      begin
        errors.add(:package_manager, :blank) unless package_manager.present?
      rescue ArgumentError
        errors.add(
          :package_manager,
          "Invalid package_manager #{@package_manager.inspect}. "\
          "Must be one of (#{acceptable_package_managers})"
        )
      end
    end

    def acceptable_package_managers
      Types::PackageManager.to_a.map { |t| t.name.to_s }.join(", ")
    end

    class Dependency
      include ActiveModel::Validations

      validates :package_name, presence: true

      # Public: The name of dependency
      #
      # Returns String
      attr_reader :package_name

      # Public: The normalized requirements string.
      #
      # Returns String
      attr_reader :requirements

      # Public: The dependency scope.
      #
      # Returns Types::Scope
      attr_reader :scope

      def initialize(package_name:, requirements:, scope:)
        @package_name = package_name
        @requirements = requirements
        @scope        = Types::Scope.coerce(scope)
      end

      # Public: Is the dependency malformed?
      #
      # Returns Boolean
      def malformed?
        @malformed
      end

      def inspect
        "#<Dependency #{attributes}>"
      end

      def ==(other)
        return unless other.is_a?(Dependency)

        attributes == other.attributes
      end

      def to_h
        # Get rid of the "@"s in instance variables
        hsh = attributes.each_with_object({}) do |(k, v), hsh|
          key = k.to_s.gsub(/^@/, "").to_sym
          hsh[key] = v
        end
      end

      protected

      def attributes
        {
          package_name: package_name,
          scope:        scope,
          requirements: requirements,
        }
      end
    end
  end
end
