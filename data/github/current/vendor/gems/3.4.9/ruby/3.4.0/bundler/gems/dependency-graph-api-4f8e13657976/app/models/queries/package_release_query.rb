module Queries
  class PackageReleaseQuery
    class InvalidRequirementsException < ArgumentError
      def initialize(requirements)
        @requirements = requirements
      end

      def message
        "Invalid requirements '#{@requirements}'"
      end
    end

    def initialize(package_name:, package_manager:, **options)
      @package_name    = package_name
      @package_manager = Types::PackageManager.coerce(package_manager)
      @options         = options
    end

    def results
      results = scoped
        .sort_by(&:parsed_version)
        .reverse
        .select do |release|
          requirement_set.cover?(release.parsed_version)
        end

      results.empty? && default_to_latest? ? latest : results
    end

    private

    attr_reader :package_name, :package_manager, :options

    def scoped
      return [] unless package.present?

      scope = releases.latest_first
      scope = scope.matching_requirement_set(requirement_set) if requirements?
      scope = scope.published unless include_unpublished?
      scope
    end

    def default_to_latest?
      options[:default_to_latest]
    end

    def include_unpublished?
      options[:include_unpublished]
    end

    def latest
      return [] unless package.present?

      scope = package.releases
      scope = scope.published unless include_unpublished?
      latest_release = scope.latest
      latest_release.present? ? [latest_release] : []
    end

    def limit
      options.fetch(:limit, 30)
    end

    def releases
      package.releases.limit(limit)
    end

    def requirements?
      requirements.present?
    end

    def requirements
      options[:requirements]
    end

    def requirement_set
      @requirement_set ||= Versioning::RequirementSet
        .deserialize(requirements, **{
          on_error: ->(range) {
            raise InvalidRequirementsException.new(requirements)
          },
          allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager),
        })
    end

    def package
      Package.for_package_manager(package_manager).with_name(package_name).first
    end
  end
end
