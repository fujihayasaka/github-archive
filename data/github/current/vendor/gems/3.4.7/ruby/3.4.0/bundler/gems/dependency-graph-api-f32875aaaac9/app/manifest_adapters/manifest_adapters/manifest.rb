
class ManifestAdapters::Manifest
  # Public: The manifest package manager
  #
  # Returns Types::PackageManager
  attr_reader :package_manager

  # Public: The manifest type
  #
  # Returns Types::ManifestType
  attr_reader :manifest_type

  # Public: The name of the package or project
  #
  # Returns String|Nil
  attr_reader :dependent_name

  # Public: The version of the package or project
  #
  # Returns String|Nil
  attr_reader :dependent_version

  # Public: File basename.
  #
  # Returns String
  attr_reader :filename

  # Public: File path. A path of "" indicates a file at the root.
  #
  # Returns String
  attr_reader :path

  # Public: Git revision.
  #
  # Returns String
  attr_reader :git_ref

  # Public: Time of manifest push.
  #
  # Returns Time
  attr_reader :pushed_at

  # Public: The github/github repository ID
  #
  # Returns Integer
  attr_reader :github_repository_id

  # Public: The github/github owner ID
  #
  # Returns Integer
  attr_reader :github_owner_id

  # Public: The repository name with owner
  #
  # Returns String
  attr_reader :repository_nwo

  # Public: The repository stargazer count
  #
  # Returns Integer
  attr_reader :repository_stargazer_count

  # Public: Is the manifest from a private repository
  #
  # Returns Bool
  attr_reader :visibility_private

  # Public: Is the manifest part of a backfill
  #
  # Returns Bool
  attr_reader :is_backfill

  # Public: The class that parsed the manifest
  #
  # Returns Class
  attr_reader :parser_class

  def initialize(package_manager:, manifest_type:, dependent_name:,
                  dependent_version: nil, path:, filename:, git_ref:,
                  pushed_at:, github_repository_id:, github_owner_id: nil,
                  repository_nwo:, repository_stargazer_count:,
                  visibility_private:, fork:, malformed:, dependencies:, is_backfill: false, parser_class: nil)
    @package_manager            = Types::PackageManager.coerce(package_manager) if package_manager
    @manifest_type              = Types::Manifest.coerce(manifest_type) if manifest_type
    @dependent_name             = dependent_name
    @dependent_version          = dependent_version
    @filename                   = filename
    @path                       = path
    @git_ref                    = git_ref
    @pushed_at                  = pushed_at
    @github_repository_id       = github_repository_id
    @github_owner_id            = github_owner_id
    @repository_nwo             = repository_nwo
    @repository_stargazer_count = repository_stargazer_count
    @fork                       = !!fork
    @visibility_private         = !!visibility_private
    @dependencies               = Array(dependencies)
    @malformed                  = malformed
    @is_backfill                = is_backfill
    @parser_class               = parser_class
  end

  # Public: Is the manifest from a fork?
  #
  # Returns Boolean
  def fork?
    @fork
  end

  # Public: Does the manifest belongs to a private repository?
  #
  # Returns Boolean
  def private_repository?
    @visibility_private
  end

  # Public: Is the manifest malformed?
  #
  # Returns Boolean
  def malformed?
    @malformed
  end

  def dependencies
    @dependencies.reject(&:malformed?)
  end

  def ==(other)
    return unless other.is_a?(self.class)

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
    instance_variables.map do |ivar|
      [ivar, instance_variable_get(ivar)]
    end.to_h
  end

  class Dependency
    # Public: The normalized name of the dependency.
    #
    # Returns String
    attr_reader :package_name


    # Public: The label of dependency as it appears in the source.
    #
    # A manifest may reference a dependency using a non-canonical name.
    # For instance, names in Python's requirements.txt are implicitly
    # normalized according to https://www.python.org/dev/peps/pep-0503.

    # Public: The normalized requirements string.
    #
    # See https://github.com/github/dependency-graph-api/blob/master/docs/tables.md#requirements-syntax for syntax.
    #
    # Returns String
    attr_reader :requirements

    # Public: The requirements string as it appears in manifest.
    #
    # Returns String
    attr_reader :raw_requirements

    # Public: The dependency scope.
    #
    # Returns Types::Scope
    attr_reader :scope

    def initialize(package_name:, requirements:, raw_requirements: nil, scope:, malformed: false)
      @package_name = package_name
      @requirements = requirements
      @raw_requirements = raw_requirements
      @scope        = Types::Scope.coerce(scope)
      @malformed    = malformed
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

    # Public: Creates a hash of dependency properties
    # This enables us to compare dependencies for uniqueness
    #
    # Returns a hash of a dependency
    def hash
      [package_name, requirements, raw_requirements, scope].hash
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

    alias :eql? :==

    protected

    def attributes
      instance_variables.map do |ivar|
        [ivar, instance_variable_get(ivar)]
      end.to_h
    end
  end
end
