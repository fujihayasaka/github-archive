class ManifestFactory
  attr_reader :github_repo_id, :git_ref, :manifest_attrs, :repository, :manifest, :github_owner_id

  MANIFEST_DEFAULTS = {
    manifest_type:   Types::Manifest[:gemfile],
    package_manager: Types::PackageManager[:rubygems],
  }

  def initialize(repository: nil, github_repo_id: nil, github_owner_id: nil, git_ref: SecureRandom.hex, **manifest_attrs)
    if repository.present?
      @repository = repository
    else
      @github_repo_id = github_repo_id || default_github_repo_id
    end
    @git_ref        = git_ref
    @manifest_attrs = manifest_attrs
    @github_owner_id = github_owner_id
  end

  def create
    @repository ||= Repository
      .where(github_repository_id: github_repo_id)
      .first_or_create!

    @repository.update!(github_owner_id: github_owner_id) if github_owner_id

    @manifest = @repository
      .manifests
      .where(manifest_attrs)
      .first_or_create!

    abstract_dependencies = []
    dependencies = []
    dependency_attrs.each do |attrs|
      package_name = attrs.fetch(:package_name)
      abstract_dependencies << AbstractRepositoryDependency.new(
        repository: repository,
        package_manager: manifest.package_manager,
        package_name: package_name
      )
      dependencies << new_dependency(package_name,
                                     attrs.fetch(:requirements),
                                     **attrs.except(:package_name, :requirements))
    end
    AbstractRepositoryDependency.import(abstract_dependencies, on_duplicate_key_ignore: true)
    ManifestDependency.import(dependencies)
    DependencyGraph::ManifestDependencyReplicator.new.to_manifest_entries(dependencies)

    manifest
  end

  def get
    manifest
  end

  def update_repository(attrs)
    @repository.update(attrs)

    self
  end

  def update_manifest(attrs)
    @manifest.update(attrs)

    self
  end

  def add_dependency(package_name, requirements, **attrs)
    repository.abstract_dependencies.where({
      package_manager: manifest.package_manager,
      package_name:    package_name,
    }).first_or_create!

    new_dependency(package_name, requirements, **attrs).save!

    self
  end

  private

  def new_dependency(package_name, requirements, **attrs)
    requirements = Versioning::RequirementSet.deserialize(requirements, allow_named_versions: true)

    serialized_reqs = requirements.serialize

    ManifestDependency.new({
      manifest: manifest,
      package_name: package_name,
      package_manager: manifest.package_manager,
      requirements: serialized_reqs,
      encoded_lower_bound: requirements.encoded_lower_bound,
      encoded_upper_bound: requirements.encoded_upper_bound,
      last_seen_at_revision: manifest.revision,
    }.merge(attrs))
  end

  def default_github_repo_id
    Repository.maximum(:github_repository_id).to_i + 1
  end

  def manifest_attrs # rubocop:disable Lint/DuplicateMethods
    attrs = MANIFEST_DEFAULTS.merge({
      latest_git_ref: @git_ref,
      last_pushed_at: Time.now,
    })
    manifest_type_from_filename = Types::Manifest.find { |t| t.human_name == @manifest_attrs[:filename] }
    if manifest_type_from_filename.present?
      attrs[:manifest_type] = manifest_type_from_filename.to_sym
      attrs[:package_manager] = manifest_type_from_filename.package_manager.to_sym
    end
    return attrs.merge(@manifest_attrs).except(:dependencies)
  end

  def dependency_attrs
    Array(@manifest_attrs[:dependencies])
  end
end
