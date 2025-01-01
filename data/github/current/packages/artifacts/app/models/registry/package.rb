# typed: false
# frozen_string_literal: true

class Registry::Package < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification
  include GitHub::UTF8
  include Registry::PackageDownloadStatsService
  include Configurable::PackageAvailability

  self.table_name = :registry_packages
  # Public: Get displayable type names for all publicly supported types.
  #
  # Returns Hash { symbol => String }
  def self.pretty_type_names
    types = self.enabled_types
    PRETTY_TYPE_NAMES.slice(*types)
  end

  # Public: Get package type from language.
  #
  # Returns symbol or nil.
  def self.package_type_for_language(language)
    LANGUAGE_TO_PACKAGE_TYPE[language]
  end

  def self.with_owner_and_name_and_type(owner_id, package_name, package_type)
    Registry::Package.where(owner_id: owner_id, name: package_name, package_type: package_type).first
  end

  def self.with_name_and_type(package_name, package_type, registry_package_type)
    Registry::Package.where(name: package_name)
      .where("package_type=? OR registry_package_type=?",
            package_types[package_type], registry_package_type).first
  end

  # Deprecated. Can be replaced with just passing the package_type directly
  # but is used in many locations so we're keeping the method around for now.
  def self.symbolize_package_type(package_type)
    package_type.to_sym if package_types[package_type].present?
  end

  def self.package_data_for_type(package_type)
    if package_type.is_a? String
      package_type = self.translate_pretty_name_to_package_type(package_type)
    end

    # Owner Ids for all packages published
    total_pkgs_published = Registry::Package.where(package_type: package_type).pluck("owner_id")
    # Distinct owner ids, sorted by descending total package count
    distinct_owner_ids = total_pkgs_published.group_by(&:itself).transform_values(&:count).sort_by { |_k, v| v }.reverse.map(&:first)
    distinct_owners_to_enumerate = User.find(distinct_owner_ids.slice(0, Registry::Package::ENUMERATE_COUNT)) # maintains order of ids passed in

    package_type_name = PACKAGE_TYPE_SYM[package_type].to_s
    package_type_pretty_name = self.translate_package_id(package_type)

    Registry::PackageData.new(
      package_type,
      total_pkgs_published.count,
      distinct_owner_ids.length,
      distinct_owners_to_enumerate,
      package_type_name,
      package_type_pretty_name
    )
  end

  def self.page_logins_by_package_type(package_type, page)
    # Owner Ids for all packages published
    total_pkgs_published = Registry::Package.where(package_type: package_type).pluck("owner_id")
    distinct_owner_ids = total_pkgs_published.group_by(&:itself).transform_values(&:count).sort_by { |_k, v| v }.reverse.map(&:first)

    User.find(distinct_owner_ids).paginate(page: page)
  end

  # Gets total download counts for all versions of a package for a set of
  # package ids. Uses a batched query.
  #
  # Returns: Hash { int => int }
  def self.total_download_counts_for_ids(package_ids)
    batched_downloads_in_range(package_ids)
  end

  # Gets last 30 day download counts for all versions of a package for a set of
  # package ids. Uses a batched query.
  #
  # Returns: Hash { int => int }
  def self.thirty_day_download_counts_for_ids(package_ids)
    batched_downloads_in_range(package_ids, 30.days.ago.beginning_of_day, Time.now.end_of_day)
  end

  def self.batched_downloads_in_range(package_ids, start_time = nil, end_time = nil)
    if start_time && end_time
      # If we put the time condition on the where clause, it'll filter out the
      # empty rows from the left join. So we need to put the time condition on
      # the JOINS ON clause.
      join_condition = "LEFT OUTER JOIN `package_download_activities` ON `package_download_activities`.`package_id` = `registry_packages`.`id` AND (`package_download_activities`.`started_at` BETWEEN ? AND ?)"
      query = self.joins(sanitize_sql_array([join_condition, start_time, end_time]))
    else
      query = self.left_joins(:downloads)
    end

    query = query.where(id: package_ids)
      .select("registry_packages.id, package_download_activities.package_version_id, SUM(package_download_activities.package_download_count) as downloads_count")
      .group("package_download_activities.package_version_id")

    raw_sums_by_version_id = query.each_with_object({}) { |p, h| h[p.package_version_id] = p.downloads_count.to_i if p.package_version_id }
    file_counts_by_version_id = Registry::PackageVersion
      .not_deleted
      .where(id: raw_sums_by_version_id.keys)
      .pluck(:id, :files_count)
      .to_h

    query.each_with_object(Hash.new { |h, k| h[k] = [] }) do |result, h|
      # Return download count of 0 if no package version was found or if
      # the package version has no files.
      file_count = file_counts_by_version_id[result.package_version_id]
      if file_count.nil? || file_count == 0
        h[result.id] = [0]
        next
      end

      version_download_count = raw_sums_by_version_id[result.package_version_id] || 0
      version_downloads = (version_download_count / file_count.to_f).ceil
      h[result.id] << version_downloads
    end.map { |id, counts| [id, counts.reduce(0, :+)] }.to_h
  end

  belongs_to :repository, required: true
  belongs_to :owner, class_name: "User"
  validates :owner_id, presence: true

  validate :check_registry_package_name

  # rubocop:todo Rails/InverseOf
  has_many :package_versions,
    class_name: "Registry::PackageVersion",
    foreign_key: :registry_package_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf
  has_many :package_files, through: :package_versions, source: :files
  # rubocop:todo Rails/InverseOf
  has_many :tags,
    class_name: "Registry::Tag",
    foreign_key: :registry_package_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf
  has_many :downloads,
    class_name: "Registry::PackageDownloadActivity",
    dependent: :delete_all

  # The version tagged `latest` or the most recent version if none tagged.
  # rubocop:todo Rails/InverseOf
  has_one :latest_version, -> (package) { merge(Registry::PackageVersion.not_deleted.latest(true, package.package_type)) },
    class_name: "Registry::PackageVersion",
    foreign_key: :registry_package_id
  # rubocop:enable Rails/InverseOf

  def name_with_owner(separator = "/")
    "#{async_owner.sync}#{separator}#{self.name}"
  end

  before_validation :sync_owner_id
  before_validation :normalize_name_characters

  validates_presence_of :name
  validates_presence_of :package_type
  validates_associated :package_versions

  after_commit :synchronize_search_index

  scope :private_scope, -> { joins(:repository).where("repositories.public = ?", false) }
  scope :public_scope, -> { joins(:repository).where("repositories.public = ?", true) }
  scope :with_active_versions, -> { joins(:package_versions).merge(Registry::PackageVersion.not_deleted).distinct }
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :migratable, ->(registry_package_type, unmigrated_only: true, failed_only: false, is_error_retry: false, error_only: false, migrated_only: false, unmigrated_and_inprogress: false) {
    where("registry_packages.package_type = ? OR registry_packages.registry_package_type = ?", package_types[registry_package_type], registry_package_type)
      .where("registry_packages.deleted_at IS NULL OR registry_packages.deleted_at >= ?", Time.now.utc.ago(30.days))
      .joins(:package_versions)
      .merge(Registry::PackageVersion.migratable(registry_package_type, unmigrated_only: unmigrated_only, failed_only: failed_only, is_error_retry: is_error_retry, error_only: error_only, migrated_only: migrated_only, unmigrated_and_inprogress: unmigrated_and_inprogress))
      .distinct
  }

  scope :unmigrated_only_deleted, ->(registry_package_type) {
    where("registry_packages.package_type = ? OR registry_packages.registry_package_type = ?", package_types[registry_package_type], registry_package_type)
      .where("registry_packages.deleted_at IS NOT NULL")
      .joins(:package_versions)
      .merge(Registry::PackageVersion.unmigrated_only_deleted(registry_package_type))
      .distinct
  }

  scope :any_deleted_version_migrated, ->(registry_package_type) {
    where("registry_packages.package_type = ? OR registry_packages.registry_package_type = ?", package_types[registry_package_type], registry_package_type)
      .where("registry_packages.deleted_at IS NOT NULL")
      .joins(:package_versions)
      .merge(Registry::PackageVersion.any_deleted_version_migrated(registry_package_type))
      .distinct
  }

  scope :any_package_exists, ->(registry_package_type) {
    where("registry_packages.package_type = ? OR registry_packages.registry_package_type = ?", package_types[registry_package_type], registry_package_type)
    .limit(1)
  }

  # All maven+rubygems, + unmigrated docker, nuget, and npm packages
  scope :unmigrated, -> {
    where("registry_packages.package_type = 3 OR registry_packages.registry_package_type = 'docker'")
      .where("registry_packages.deleted_at IS NULL OR registry_packages.deleted_at >= ?", Time.now.utc.ago(30.days))
      .joins(:package_versions)
      .merge(Registry::PackageVersion.migratable("docker", unmigrated_only: true))
    .or(where("registry_packages.package_type = 0 OR registry_packages.registry_package_type = 'npm'"))
      .where("registry_packages.deleted_at IS NULL OR registry_packages.deleted_at >= ?", Time.now.utc.ago(30.days))
      .joins(:package_versions)
      .merge(Registry::PackageVersion.migratable("npm", unmigrated_only: true))
    .or(where("registry_packages.package_type = 5 OR registry_packages.registry_package_type = 'nuget'"))
      .where("registry_packages.deleted_at IS NULL OR registry_packages.deleted_at >= ?", Time.now.utc.ago(30.days))
      .joins(:package_versions)
      .merge(Registry::PackageVersion.migratable("nuget", unmigrated_only: true))
    .or(where("registry_packages.package_type = 1 OR registry_packages.registry_package_type = 'rubygems'"))
      .where("registry_packages.deleted_at IS NULL OR registry_packages.deleted_at >= ?", Time.now.utc.ago(30.days))
      .joins(:package_versions)
      .merge(Registry::PackageVersion.migratable("rubygems", unmigrated_only: true))
    .or(where("registry_packages.package_type = 2 AND registry_packages.registry_package_type = 'maven'"))
    .distinct
  }

  enum :package_type, { npm: 0, rubygems: 1, maven: 2, docker: 3, debian: 4, nuget: 5 }
  PACKAGE_TYPE_SYM = { 0 => :npm, 1 => :rubygems, 2 => :maven, 3 => :docker, 4 => :debian, 5 => :nuget }
  PUBLICLY_SUPPORTED_TYPES = %i(npm rubygems maven docker nuget)
  BLOCKED_GRAPHQL_TYPES = %w(npm nuget rubygems)
  PRETTY_TYPE_NAMES = {
    npm: "npm",
    rubygems: "RubyGems",
    maven: "Maven",
    docker: "Docker",
    debian: "Debian",
    nuget: "NuGet",
  }

  LANGUAGE_TO_PACKAGE_TYPE = {
    javascript: :npm,
    ruby: :rubygems,
    java: :maven,
    docker: :docker,
    "c#": :nuget,
  }

  attr_accessor :total_download_count

  PUBLIC_PACKAGE_DELETE_ERR_MSG = "Publicly visible packages with a version with more than #{PUBLIC_VERSION_DELETE_LIMIT} downloads cannot be deleted. Contact GitHub support for further assistance."

  # Public: Translates an integer id to its Pretty Type Name
  def self.translate_package_id(id)
    PRETTY_TYPE_NAMES[PACKAGE_TYPE_SYM[id]]
  end

  # Internal: An array of strings of all supported Debian architectures
  DEBIAN_ARCHITECTURES = %w(i386 amd64 armel armhf arm64 mips mips64el mipsel ppc64el s390x)

  def self.translate_pretty_name_to_package_type(pretty_name)
    package_types[pretty_name.downcase.to_sym]
  end

  ENUMERATE_COUNT = 2

  def self.supported_package_type_values
    package_types.slice(*PUBLICLY_SUPPORTED_TYPES).values
  end

  def self.publicly_supported_migrated_types(user)
    publicly_supported_migrated_types = %i()
    publicly_supported_migrated_types.push(:npm, :nuget, :rubygems) if !GitHub.enterprise?
    publicly_supported_migrated_types.push(:maven) if GitHub.flipper[:packages_maven_registry_v2].enabled?(user)
    publicly_supported_migrated_types
  end

  def self.enabled_types
    case Configurable::PackageAvailability.package_availability

    when Configurable::PackageAvailability::ENABLED
      supported_package_type_values.map { |package_type| PACKAGE_TYPE_SYM[package_type] }
    when Configurable::PackageAvailability::MANAGED
      key = "repository:packages:enabled_types"
      enabled_types = GitHub.cache.fetch(key, ttl: 10.seconds) do
        enabled_package_types
      end

      enabled_types.map { |package_type| PACKAGE_TYPE_SYM[package_type] }
    else
      []
    end
  end

  delegate :public?, to: :repository, prefix: true

  # Public: Whether the given user can see this registry package.
  def readable_by?(actor)
    repository && repository.readable_by?(actor)
  end

  # Public: Returns the associated package version matching `version`.
  #
  # Returns: Registry::PackageVersion
  def version_by_version_string(version, owner: self.owner, include_deleted: false)
    versions = package_versions.where(version: version)
    versions = versions.not_deleted unless include_deleted
    if GitHub.flipper[:packages_docker_v1_migrated].enabled?(owner) && self.docker?
      versions = versions.where(migration_state: :unmigrated)
    end

    versions.first
  end

  # Public: Returns the associated package version matching `shasum`.
  #
  # Returns: Registry::PackageVersion
  def version_by_sha256(shasum, owner: self.owner, include_deleted: false)
    versions = package_versions.where(sha256: shasum)
    versions = versions.not_deleted unless include_deleted
    if GitHub.flipper[:packages_docker_v1_migrated].enabled?(owner) && self.docker?
      versions = versions.where(migration_state: :unmigrated)
    end
    versions.first
  end

  # Public: Returns the associated package version matching `version`, `platform`.
  #
  # Returns: Registry::PackageVersion
  def version_by_platform(version, platform, owner: self.owner, include_deleted: false)
    versions = package_versions.where(version: version, platform: platform)
    versions = versions.not_deleted unless include_deleted
    if GitHub.flipper[:packages_docker_v1_migrated].enabled?(owner) && self.docker?
      versions = versions.where(migration_state: :unmigrated)
    end
    versions.first
  end

  def prerelease_versions
    package_versions.joins(:release).where(releases: { prerelease: true })
  end

  def shell_safe_name
    Shellwords.escape(utf8(name))
  end

  def color
    case package_type.to_sym
    when :rubygems
      ruby = Linguist::Language.find_by_name("Ruby")
      ruby.color
    when :npm
      js = Linguist::Language.find_by_name("Javascript")
      js.color
    when :maven
      java = Linguist::Language.find_by_name("Java")
      java.color
    when :docker
      "#046fb3" # Docker whale - https://www.docker.com/brand-guidelines
    when :debian
      "#d61053" # Debian logo - https://www.debian.org/logos/
    when :nuget
      "#2B9CDF" # Nuget logo - https://commons.wikimedia.org/wiki/File:NuGet_project_logo.svg
    else
      "#ccc"
    end
  end

  def target_for_conditional_access
    owner
  end

  def sync_owner_id
    self.owner_id = repository.owner_id
  end

  def transfer(new_owner:, old_owner:, actor:, transferred_at: Time.now.utc)
    update(owner_id: new_owner.id)

    data = {
      actor: actor,
      package: self,
      size: package_versions.not_deleted.joins(:package_files).sum("package_files.size"),
      transferred_at: transferred_at,
      storage_service: "AWS_S3",
      user_agent: GitHub.context[:user_agent].to_s,
      repository: repository,
      previous_owner_id: old_owner.id,
      previous_owner_global_id: old_owner.global_relay_id,
    }

    case old_owner
    when ::Organization
      data[:previous_owner_org] = old_owner
    else
      data[:previous_owner_user] = old_owner
    end

    GlobalInstrumenter.instrument("packages.package_transferred", data)
  end

  def normalize_name_characters
    return unless name_changed?

    normalized_name = utf8(self.name.to_s)
    normalized_name.gsub!(/[^[[:word:]][[:blank:]][[:punct:]]]/, "")
    normalized_name.squish!
    self.name = normalized_name
  end

  def synchronize_search_index
    if destroyed? || repository.nil?
      RemoveFromSearchIndexJob.perform_later("registry_package", self.id, self.repository_id)
    else
      Search.add_to_search_index("registry_package", self.id)
    end
  end

  # Public: Return a Hash of information for the source registry of this package.
  #
  # For the moment, this will simply return a Hash based off of the registry_package_type, however when we have public
  # users of the Package Platform, this will return metadata for their registry.
  #
  # Returns a Hash containing information about the source registry.
  def source_registry
    if self.class.package_types.keys.include?(registry_package_type.to_s)
      registry_path = case registry_package_type
      when "docker" then repository.name_with_owner
      when "npm" then "@#{owner.login}"
      else owner.login
      end

      {
        about_url: "#{GitHub.help_url}/packages/learn-github-packages/introduction-to-github-packages",
        name: "GitHub #{registry_package_type} registry",
        type: registry_package_type,
        url: "#{GitHub.urls.registry_url(registry_package_type)}#{registry_path}", # GitHub.urls.registry_url includes trailing slash
        vendor: "GitHub Inc"
      }
    end
  end

  def check_registry_package_name
    rp = Registry::Package.with_owner_and_name_and_type(self.repository.owner_id, self.name, self.package_type)

    # registry package not created yet
    return true if rp.nil?

    # registry package created and associated with another repo
    return errors.add(:registry_package, "is already associated with another repository") unless rp.repository.id == self.repository_id

    true
  end

  def platform_type_name
    "Package"
  end

  def deleted?
    deleted_at.present?
  end

  def can_be_deleted?
    true
  end

  def delete!(actor: nil, via_actions: false, user_agent: "", force_delete: false)
    return unless deleted_at.nil?

    transaction do
      now = Time.now.utc
      versions = package_versions.not_deleted
      version_ids = versions.pluck(:id).map(&:to_i)
      filtered_versions = versions.select { |version| !version.is_docker_base_layer? }

      # https://github.com/github/c2c-package-registry/issues/3297
      delete_blocked = repository.public? && filtered_versions.any? { |v| v.delete_blocked? }
      raise PackageDeletionError.new(PUBLIC_PACKAGE_DELETE_ERR_MSG) if !force_delete && delete_blocked

      # it is necessary to reload versions after update_all since that method
      # circumvents much of ActiveRecord's checks and callbacks
      versions.update_all deleted_at: now, updated_at: now
      versions = package_versions.where(id: version_ids)

      self.original_name = self.name
      self.name = "deleted_#{SecureRandom.uuid}"
      self.deleted_at = now
      save!

      storage_bytes = 0
      versions.each do |pv|
        file_sizes = pv&.files.pluck(:size)
        storage_bytes += file_sizes.sum

        params = {
          actor: actor,
          package: self,
          version: pv,
          size: file_sizes.sum,
          files_count: file_sizes.count,
          deleted_at: now,
          storage_service: "AWS_S3",
          user_agent: user_agent,
          via_actions: via_actions,
          bulk_delete: true
        }
        GlobalInstrumenter.instrument("package_registry.package_version_deleted", params)
      end
      instrument_delete(
        actor: actor,
        via_actions: via_actions,
        user_agent: user_agent,
        version_count: filtered_versions.count,
        storage_bytes: storage_bytes,
        deleted_at: now
      )
    end
  end

  def instrument_delete(actor:, via_actions: false, user_agent: "", version_count: 0, storage_bytes: 0, deleted_at: Time.now.utc)
    GlobalInstrumenter.instrument("package_registry.package_deleted", {
      actor: actor,
      via_actions: via_actions,
      user_agent: user_agent,
      package: self,
      deleted_at: deleted_at,
      version_count: version_count,
      storage_bytes: storage_bytes,
      storage_service: "AWS_S3"
    })
  end

  class PackageDeletionError < StandardError; end
  class PackageConflictError < StandardError; end

  def restore!(actor: nil, via_actions: false, user_agent: "")
    if repository.packages.where.not(id: id).exists?(package_type: package_type, name: original_name)
      raise PackageConflictError.new("Another package exists with the same name")
    end

    return if deleted_at.nil?

    within_30_days = Time.now.utc.ago(30.days) <= deleted_at
    raise PackageDeletionError.new("Cannot restore package after 30 days") unless within_30_days

    transaction do
      restored_versions = package_versions.where(deleted_at: deleted_at)
      restored_version_ids = restored_versions.pluck(:id).map(&:to_i)
      version_count = restored_versions.count
      total_size = restored_versions.joins(:package_files).sum("package_files.size")

      now = Time.now.utc
      # same deal as above, we have to reload the restored_versions after we commit the update
      restored_versions.update_all deleted_at: nil, updated_at: now
      restored_versions = package_versions.where(id: restored_version_ids)

      # make sure all the versions get properly named back; this is mostly to guard us against the legacy behavior
      # where versions were renamed even when it was the entire package being deleted
      # this is expensive and does not scale, but we should be able to remove after some time
      renamed_versions = restored_versions.where.not(original_name: nil)
      renamed_versions.each { |v| v.update(version: v.original_name, original_name: nil) }

      restored_versions.each do |pv|
        # Emit file published events for billing, 1 per file published
        file_sizes = pv&.files.pluck(:size)
        pv&.files.each do |file|
          params = {
            actor: actor,
            package: self,
            version: pv,
            size: file_sizes.sum,
            files_count: file_sizes.count,
            published_at: now,
            storage_service: "AWS_S3",
            via_actions: via_actions,
            file: file,
            user_agent: user_agent,
          }

          GlobalInstrumenter.instrument("package_registry.package_file_published", params)
        end

        # Emit version published event for the audit log, 1 per version published
        GlobalInstrumenter.instrument("package_registry.package_version_published", {
          actor: actor,
          package: self,
          version: pv,
          size: file_sizes.sum,
          files_count: file_sizes.count,
          published_at: now,
          storage_service: "AWS_S3",
          via_actions: via_actions,
          user_agent: user_agent,
          republished: true,
          bulk_publish: true
        })
      end
      package_deleted_name = name
      self.deleted_at = nil
      self.name = original_name
      self.original_name = nil
      save!

      GlobalInstrumenter.instrument("package_registry.package_published", {
        actor: actor,
        package: self,
        published_at: updated_at,
        storage_service: "AWS_S3",
        version_count: version_count,
        total_size: total_size,
        via_actions: via_actions,
        user_agent: user_agent,
        republished: true,
        package_deleted_name: package_deleted_name
      })
    end
  end

  def restore(actor: nil, via_actions: false, user_agent: "")
    restore!(actor: actor, via_actions: via_actions, user_agent: user_agent)
    true
  rescue PackageConflictError, PackageDeletionError
    false
  end

  def migrated?
    package_versions.exclude_docker_base_layer.unmigrated.count == 0
  end

  def has_versions_excluding_base_layer?
    package_versions.exclude_docker_base_layer.count > 0
  end

  def partially_migrated?
    package_versions.exclude_docker_base_layer.migrated.count > 0 && !migrated?
  end

  def under_migration?
    package_versions.exclude_docker_base_layer.under_migration.count != 0
  end

  def restrict_delete_restore_on_migration?
    under_migration? && ((GitHub.enterprise? && registry_package_type == "docker") || registry_package_type == "npm" || registry_package_type == "rubygems" || registry_package_type == "nuget")
  end

  def restrict_graphql_apis?
    !GitHub.enterprise? && BLOCKED_GRAPHQL_TYPES.include?(registry_package_type)
  end

  def migratable?
    # currently only docker (v1) packages either not deleted or deleted in last 30 days can be migrated
    # TODO: do we care about versions?
    (registry_package_type == "docker" || registry_package_type == "npm" || registry_package_type == "rubygems" || registry_package_type == "nuget") && (!deleted? || deleted_at >= Time.now.utc.ago(30.days))
  end

  def active?
    package_versions.not_deleted.latest(false).present?
  end

  def downloads_in_range(start_time, end_time)
    self.class.batched_downloads_in_range(id, start_time, end_time)[id]
  end

  def visibility
    repository.public_or_private_visibility
  end
end
