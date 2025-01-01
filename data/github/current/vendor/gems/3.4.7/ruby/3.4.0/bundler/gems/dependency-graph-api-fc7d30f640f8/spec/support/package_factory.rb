class PackageFactory
  attr_reader :package, :release

  def initialize(package_name, version, package_manager = nil)
    @package_name = package_name
    @version = version
    @package_manager = package_manager || Types::PackageManager[:rubygems]
  end

  def create(release_attributes = {}, package_attributes = {})
    @package = Package
      .create_with(package_manager: package_manager, label: @package_name)
      .create_with(package_attributes)
      .where(name: @package_name)
      .first_or_create!

    @release = @package
      .releases
      .create_with(release_attributes)
      .create_with(encoded: encoded_version)
      .create_with(package_manager: package_manager)
      .create_with(package_name: @package_name)
      .where(name: @version)
      .first_or_create!
  end

  # This method will force the creation of the package as well as the
  # package release instead of reusing them if they exist.
  # If they exist, this method will raise.
  def create!(release_attributes = {}, package_attributes = {})
    @package = Package
      .create_with(package_manager: package_manager, label: @package_name)
      .create_with(package_attributes)
      .where(name: @package_name)
      .create!

    @release = @package
      .releases
      .create_with(release_attributes)
      .create_with(encoded: encoded_version)
      .create_with(package_manager: package_manager)
      .create_with(package_name: @package_name)
      .where(name: @version)
      .create!
  end

  def update_package(attrs)
    @package.update!(attrs)

    self
  end

  def update_package_repository(attrs)
    repo = @package.repository
    if repo
      repo.update!(attrs)
    else
      attrs[:github_repository_id] = attrs.delete(:repository_id) || @package.repository_id
      Repository.create!(attrs)
    end

    self
  end

  def update_package_release(attrs)
    @release.update!(attrs)

    self
  end

  def update_repository_mapping(github_repository_id:, repository_id_certainty: PackageToRepoMapping::Certainty::UNVERIFIED)
    self.update_package(github_repository_id: github_repository_id, repository_id_certainty: repository_id_certainty)
      .update_package_release(github_repository_id: github_repository_id, repository_id_certainty: repository_id_certainty)
  end

  def dependency(package_name, requirements)
    requirements = Versioning::RequirementSet.deserialize(requirements, allow_named_versions: true)

    @package.abstract_dependencies.where({
      package_name:    package_name,
      package_manager: Types::PackageManager.coerce(package_manager).serialize,
    }).first_or_create!

    @release.dependencies.where({
      package_name:        package_name,
      requirements:        requirements.serialize,
      package_manager:     package_manager,
      encoded_lower_bound: requirements.encoded_lower_bound,
      encoded_upper_bound: requirements.encoded_upper_bound,
    }).first_or_create!

    self
  end
  alias :add_dependency :dependency

  private

  attr_reader :package_manager

  def encoded_version
    Versioning::VersionParser.parse(@version, allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager)).encoded.to_i
  rescue Versioning::NoEncodedVersionError
    nil
  end
end
