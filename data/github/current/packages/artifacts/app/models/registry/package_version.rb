# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Registry::PackageVersion < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification
  include GitHub::Tracing
  include GitHub::UserContent
  include GitHub::UTF8
  include OcticonsHelper
  include Registry::PackageDownloadStatsService

  # Public: Adds an index hint
  #
  # index - the index to suggest
  #
  # Returns nothing.
  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end

  # Gets the summary for each version of a set of package version ids.
  # Uses a batched query.
  #
  # Returns: Hash { int => string }
  def self.summaries_for_ids(version_ids)
    self.left_joins(:metadata)
      .where(id: version_ids)
      .where("`registry_package_metadata`.`name` = ?", Registry::Metadatum::KEYS[:SUMMARY])
      .select("package_versions.id,registry_package_metadata.value as prefetched_summary")
      .group("registry_package_metadata.package_version_id")
      .each_with_object({}) { |p, h| h[p.id] = GitHub::Encoding.try_guess_and_transcode(p.prefetched_summary).presence }
  end

  # Gets the number of dependencies for each version of a set of package
  # version ids. Uses a batched query.
  #
  # Returns: Hash { int => int }
  def self.dependency_counts_for_ids(version_ids)
    self.left_joins(:dependencies)
      .where(id: version_ids)
      .select("package_versions.id, COUNT(registry_package_dependencies.id) as dependency_count")
      .group("registry_package_dependencies.registry_package_version_id")
      .each_with_object({}) { |p, h| h[p.id] = p.dependency_count }
  end

  def self.total_download_counts_for_ids(version_ids)
    batched_downloads_in_range(version_ids)
  end

  def self.thirty_day_download_counts_for_ids(version_ids)
    batched_downloads_in_range(version_ids, 30.days.ago.beginning_of_day, Time.now.end_of_day)
  end

  def self.fetch_sum_download_count_for_version(version_id)
    query = self.left_joins(:downloads)
    query = query.where(id: version_id)
    .select("package_versions.id, SUM(package_download_activities.package_download_count) as downloads_count")
    query.each_with_object({}) { |p, h| h[p.id] = p.downloads_count }
  end

  def self.batched_downloads_in_range(version_ids, start_time = nil, end_time = nil)
    if start_time && end_time
      # If we put the time condition on the where clause, it'll filter out the
      # empty rows from the left join. So we need to put the time condition on
      # the JOINS ON clause.
      join_condition = "LEFT OUTER JOIN `package_download_activities` ON `package_download_activities`.`package_version_id` = `package_versions`.`id` AND (`package_download_activities`.`started_at` BETWEEN ? AND ?)"
      query = self.joins(sanitize_sql_array([join_condition, start_time, end_time]))
    else
      query = self.left_joins(:downloads)
    end

    query = query.where(id: version_ids)
      .select("package_versions.id, SUM(package_download_activities.package_download_count) as downloads_count")
      .group("package_download_activities.package_version_id")

    raw_sums_by_version_id = query.each_with_object({}) { |v, h| h[v.id] = v.downloads_count.to_i }
    file_counts_by_version_id = Registry::PackageVersion
      .not_deleted
      .where(id: raw_sums_by_version_id.keys)
      .pluck(:id, :files_count)
      .to_h

    raw_sums_by_version_id.map do |id, raw_sum|
      # Return download count of 0 if the package version has no files.
      file_count = file_counts_by_version_id[id]
      if file_count.nil? || file_count == 0
        downloads = 0
      end

      downloads ||= (raw_sum / file_count.to_f).ceil
      [id, downloads]
    end.to_h
  end

  belongs_to :package, class_name: "Registry::Package", foreign_key: :registry_package_id # rubocop:todo Rails/InverseOf
  belongs_to :release, class_name: "Release"
  belongs_to :author, class_name: "User"
  belongs_to :deleted_by, class_name: "User"

  # rubocop:todo Rails/InverseOf
  has_many :dependencies,
    class_name: "Registry::Dependency",
    foreign_key: "registry_package_version_id",
    dependent: :delete_all
  # rubocop:enable Rails/InverseOf

  has_many :files,
    class_name: "Registry::File"

  has_many :manifest_entries,
    class_name: "Registry::ManifestEntry",
    dependent: :destroy
  has_many :package_files, through: :manifest_entries, source: :file

  # rubocop:todo Rails/InverseOf
  has_many :tags, class_name: "Registry::Tag",
    foreign_key: "registry_package_version_id",
    dependent: :delete_all
  # rubocop:enable Rails/InverseOf

  has_many :metadata, class_name: "Registry::Metadatum", dependent: :delete_all
  # for preloading during migration
  has_one :rubygem_readme, -> { where(name: Registry::Metadatum::KEYS[:README]) }, class_name: "Registry::Metadatum"
  has_one :rubygem_summary, -> { where(name: Registry::Metadatum::KEYS[:SUMMARY]) }, class_name: "Registry::Metadatum"

  has_many :downloads, class_name: "Registry::PackageDownloadActivity", dependent: :delete_all

  validates_presence_of :version
  validates_presence_of :author, on: :create

  after_commit :synchronize_search_index

  after_destroy_commit :destroy_package_if_last_version
  after_commit :retag_latest_version, on: [:destroy, :create]

  after_destroy_commit :ensure_delete_event_instrumented
  before_destroy :destroy_orphaned_files

  trace_method :destroy_orphaned_files

  # Public: Returns package versions, latest first. If a version is tagged 'latest'
  # it comes first, otherwise the versions are returned most recently updated first.
  #
  # Returns a scoped relation.
  # Since nuget pacakge registry doesn't contain tags for nuget it will return
  # most recently updated first
  def self.latest(exclude_docker_base_layer = true, package_type = nil)
    if package_type.present? && package_type.to_sym == :nuget
      q = order("package_versions.created_at DESC")
      q
    else
      q = joins("LEFT JOIN registry_package_tags " \
          "ON registry_package_tags.registry_package_version_id = package_versions.id " \
          "AND registry_package_tags.name = 'latest'").
        order("registry_package_tags.id DESC, package_versions.created_at DESC")

      q = q.where("package_versions.version != 'docker-base-layer'") if exclude_docker_base_layer
      q
    end
  end

  scope :unmigrated, -> {
    exclude_docker_base_layer
      .where("package_versions.migration_state = 'unmigrated' OR package_versions.migration_state = 'pending' OR package_versions.migration_state = 'retriable_error'")
      .where("package_versions.deleted_at IS NULL OR package_versions.deleted_at >= ?", Time.now.utc.ago(30.days))
  }

  scope :under_migration, -> {
    exclude_docker_base_layer
      .where("package_versions.migration_state = 'pending'")
      .where("package_versions.deleted_at IS NULL OR package_versions.deleted_at >= ?", Time.now.utc.ago(30.days))
  }

  scope :not_deleted, -> { where(deleted_at: nil) }

  scope :deleted, -> { where.not(deleted_at: nil) }

  scope :migration_in_progress, -> { where(migration_state: :pending) }

  scope :migrated, -> { where(migration_state: :complete) }

  scope :not_migrated, -> {
    where(migration_state: :unmigrated)
      .where("package_versions.deleted_at IS NULL OR package_versions.deleted_at >= ?", Time.now.utc.ago(30.days))
  }

  scope :on_repository, ->(repository_id) {
    joins(:package).where("`registry_packages`.`repository_id` = ?", repository_id)
  }

  scope :exclude_docker_base_layer, -> {
    where("package_versions.version != 'docker-base-layer' AND (package_versions.original_name != 'docker-base-layer' OR package_versions.original_name IS NULL)")
      .where("package_versions.version != 'vdocker-base-layer' AND (package_versions.original_name != 'vdocker-base-layer' OR package_versions.original_name IS NULL)")
  }

  scope :migratable, ->(registry_package_type, unmigrated_only: true, failed_only: false, is_error_retry: false, error_only: false, migrated_only: false, unmigrated_and_inprogress: false) {
    # Check version platform only for docker, as all other registry have platform as empty
    query = registry_package_type == "docker" ? exclude_docker_base_layer.where("package_versions.platform = 'docker'") : where("")
    query = query.where("package_versions.deleted_at IS NULL OR package_versions.deleted_at >= ?", Time.now.utc.ago(30.days))

    if failed_only
      query = query.where("package_versions.migration_state = 'pending'")
    elsif is_error_retry
      query = query.where("package_versions.migration_state = 'error'")
    elsif error_only
      query = query.where("package_versions.migration_state = 'retriable_error'")
    elsif unmigrated_only
      query = query.where("package_versions.migration_state = 'unmigrated' OR package_versions.migration_state = 'retriable_error'")
    elsif unmigrated_and_inprogress
      query = query.where("package_versions.migration_state = 'unmigrated' OR package_versions.migration_state = 'pending'")
    elsif migrated_only
      query = query.where("package_versions.migration_state = 'complete'")
    end

    query
  }

  scope :any_deleted_version_migrated, ->(registry_package_type) {
    # Check version platform only for docker, as all other registry have platform as empty
    query = registry_package_type == "docker" ? exclude_docker_base_layer.where("package_versions.platform = 'docker'") : where("")
    query = query.where("package_versions.deleted_at IS NOT NULL")
      .where("package_versions.migration_state = 'complete'")

    query
  }

  scope :unmigrated_only_deleted, ->(registry_package_type) {
    # Check version platform only for docker, as all other registry have platform as empty
    query = registry_package_type == "docker" ? exclude_docker_base_layer.where("package_versions.platform = 'docker'") : where("")
    query = query.where("package_versions.deleted_at IS NOT NULL")
      .where("package_versions.migration_state = 'unmigrated'")

    query
  }

  scope :unmigrated_undeleted, -> {
    where(deleted_at: nil)
    .where(migration_state: :unmigrated)
  }

  PUBLIC_PACKAGE_VERSION_DELETE_ERR_MSG = "Publicly visible package versions with more than #{PUBLIC_VERSION_DELETE_LIMIT} downloads cannot be deleted. Contact GitHub support for further assistance."

  def body
    metadata.readme
  end

  def shell_safe_version
    Shellwords.escape(utf8(version))
  end

  def body_pipeline
    GitHub::Goomba::PackageVersionPipeline
  end

  def async_body_context
    super.then do |context|
      context.merge(anchor_icon: octicon("link"))
    end
  end

  def summary
    metadata.summary
  end

  def installation_command
    metadata.installation_command
  end

  def package_manifest
    m = self.manifest
    m ||= metadata.docker_manifest unless m.present? || metadata.docker_manifest.empty?
    GitHub::Encoding.try_guess_and_transcode(m)
  end

  def serializeable_metadata
    metadata.serializeable
  end

  def trigger_create_webhook(actor_id)
    enqueue_webhook(:published, actor_id)
  end

  def trigger_update_webhook(actor_id)
    enqueue_webhook(:updated, actor_id)
  end

  def platform_type_name
    "PackageVersion"
  end

  def deleted?
    deleted_at.present?
  end

  def is_latest_version?
    self == package.latest_version
  end

  def is_docker_base_layer?
    (self.version == "docker-base-layer" || self.original_name == "docker-base-layer") && package.package_type.to_sym == :docker
  end

  def migrated?
    migration_state.to_sym == :complete
  end

  def migration_in_progress?
    migration_state.to_sym == :pending
  end

  def restrict_delete_restore_on_migration?
    migration_in_progress? && ((GitHub.enterprise? && package.registry_package_type == "docker") || package.registry_package_type == "npm" || package.registry_package_type == "rubygems" || package.registry_package_type == "nuget")
  end

  def restrict_graphql_apis?
    !GitHub.enterprise? && Registry::Package::BLOCKED_GRAPHQL_TYPES.include?(package.registry_package_type)
  end

  class PublicVersionDeletionError < StandardError; end

  # Marks the package version as deleted, hiding it from search results and
  # making it ineligible for downloads. Side effect: instruments
  # PackageVersionDeleted hydro event so the version is no longer counted
  # towards storage quota.
  #
  # Args:
  #   actor - the user who initiated this delete
  #   via_actions - whether or not this deletion came from Actions
  #   force_delete - whether or not to skip validation checks prior to deletion.
  #     Only true when call originates from repo archival.
  def delete!(actor: nil, via_actions: false, user_agent: "", force_delete: false, deleted_at: Time.now.utc, bulk_delete: false)
    owner = package.repository&.owner

    raise PackageVersionDeletionError.new(PUBLIC_PACKAGE_VERSION_DELETE_ERR_MSG) if delete_blocked?(force_delete: force_delete)

    return unless self.deleted_at.nil?

    self.original_name = version
    self.version = "deleted_#{SecureRandom.uuid}"
    self.deleted_at = deleted_at
    self.deleted_by = actor
    save!

    if package.package_type.to_sym == :docker
      delete_docker_base_layer_if_last_version(actor, force_delete, deleted_at: deleted_at)
    end

    # npm and rubygems need "latest" tags for their tooling
    retag_latest_npm_version if package.package_type.to_sym == :npm
    retag_latest_version

    # deleting the last version also deletes the package for v1
    if package.package_versions.not_deleted.count == 0 && !package.repository.nil? && !package.repository.owner.nil? && !is_docker_base_layer?
      package.deleted_at = deleted_at
      package.original_name = package.name
      package.name = "deleted_#{SecureRandom.uuid}"
      package.save!
      if !bulk_delete && !(package.package_type.to_sym == :docker && self.is_docker_base_layer?)
        package.instrument_delete(actor: actor, via_actions: via_actions, user_agent: user_agent)
      end
    end

    # only change usage if there is an owner (which is what we are billing)
    # and there are files associated with this packge version
    if owner && files.count > 0
      # azure gigabytes are 1,000,000 bytes, not rails gigabytes
      pkg_size = files.sum(:size).to_f / (1000 * 1000 * 1000).to_f
      utilization = Registry::PackageStorageUtilizations.find_by(owner: owner)
      if utilization
        new_usage = utilization.gb_used - pkg_size
        utilization.gb_used = [new_usage, 0].max
        utilization.save!
        GitHub.dogstats.increment "billing.package_registry.decrement_storage_usage_row"
      else
        GitHub.dogstats.increment "billing.package_registry.missing_storage_usage_row"
        GitHub.logger.error("method": "Registry::PackageVersion.delete!",
                           "actor": owner,
                           "package": package,
                           "message": "No storage usage entry found for owner")
      end
    end

    # Public: Returns package versions, latest first. If a version is tagged 'latest'
    file_sizes = files.pluck(:size)
    params = {
      actor: actor,
      package: package,
      version: self,
      size: file_sizes.sum,
      files_count: file_sizes.count,
      deleted_at: self.deleted_at,
      storage_service: "AWS_S3",
      user_agent: user_agent,
      via_actions: via_actions,
      bulk_delete: bulk_delete
    }

    GlobalInstrumenter.instrument("package_registry.package_version_deleted", params)
  end

  class PackageVersionDeletionError < StandardError; end
  class PackageVersionRestorationError < StandardError; end
  class PackageVersionConflictError < StandardError; end

  def restore!(actor: nil, via_actions: false, user_agent: "", bulk_restore: false)
    if package.package_versions.where.not(id: id).exists?(version: original_name)
      raise PackageVersionConflictError.new("Another package version exists with the same name")
    end

    return if self.deleted_at.nil?
    raise PackageVersionRestorationError.new("Cannot restore version for deleted package") if self.package.deleted?

    version_deleted_name = version

    self.version = original_name.present? ? original_name : version
    self.original_name = nil
    self.deleted_at = nil
    save!

    # Emit file published events for billing, 1 per file published
    file_sizes = files.pluck(:size)
    files.each do |file|
      params = {
        actor: actor,
        package: package,
        version: self,
        size: file_sizes.sum,
        files_count: file_sizes.count,
        published_at: updated_at,
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
      package: package,
      version: self,
      size: file_sizes.sum,
      files_count: file_sizes.count,
      published_at: updated_at,
      storage_service: "AWS_S3",
      via_actions: via_actions,
      user_agent: user_agent,
      republished: true,
      bulk_publish: bulk_restore,
      version_deleted_name: version_deleted_name
    })
  end

  def downloads_in_range(start_time, end_time)
    self.class.batched_downloads_in_range(id, start_time, end_time)[id]
  end

  def total_download_count
    res_hash = self.class.fetch_sum_download_count_for_version(id)
    res_hash[id]
  end

  # https://github.com/github/c2c-package-registry/issues/3297
  def delete_blocked?(force_delete: false)
    !force_delete && package.repository&.public? && downloads_total_count > PUBLIC_VERSION_DELETE_LIMIT
  end

  private

  def retag_latest_npm_version
    latest_tag = Registry::Tag.where(name: "latest", registry_package_id: registry_package_id).first
    latest_version_id = package.package_versions.not_deleted.latest&.first&.id

    return unless latest_version_id

    if latest_tag.present?
      latest_tag.registry_package_version_id = latest_version_id
      latest_tag.save
      return
    end

    latest_tag = Registry::Tag.new(name: "latest", registry_package_id: registry_package_id, registry_package_version_id: latest_version_id)
    latest_tag.save
  end

  def should_retag_version?
    package.present? && Registry::Package.exists?(package.id) && (package.rubygems?)
  end

  def destroy_package_if_last_version
    with_lock do
      package.destroy if package && package.package_versions.empty?
    end
  end

  def delete_docker_base_layer_if_last_version(actor, force_delete = false, deleted_at: Time.now.utc)
    return if package.package_versions.not_deleted.count > 1
    latest_version = package.package_versions.not_deleted.latest(false).first
    if latest_version&.version == "docker-base-layer"
      latest_version.delete!(actor: actor, via_actions: false, user_agent: "", force_delete: force_delete, deleted_at: deleted_at)
    end
  end

  def destroy_orphaned_files
    files.each do |file|
      file.destroy_if_orphaned
    end
  end

  def retag_latest_version
    return unless should_retag_version?

    latest_tag = Registry::Tag.where(name: "latest", registry_package_id: registry_package_id).first

    # Lower bound values.
    highest_version = Gem::Version.new("0.0.0")
    highest_version_id = -10

    package.reload.package_versions.pluck(:id, :version).each do |result|
      # Move to the next version unless this value is a semantic version string
      next unless !!result[1].match(Semantic::Version::SemVerRegexp)
      current_version = Gem::Version.new(result[1])
      if current_version > highest_version
        highest_version_id = result[0]
        highest_version = current_version
      end
    end

    # if we found a higher version.
    if highest_version_id > -10
      # Create a tag to point to the latest version.
      latest_tag ||= Registry::Tag.new(registry_package_id: registry_package_id, name: "latest")
      latest_tag.registry_package_version_id = highest_version_id
      latest_tag.save
    end
  end

  def ensure_delete_event_instrumented
    return if self.deleted?

    file_sizes = files.pluck(:size)
    params = {
      actor: nil,
      package: package,
      version: self,
      size: file_sizes.sum,
      files_count: file_sizes.count,
      deleted_at: Time.now,
      storage_service: "AWS_S3",
      user_agent: nil,
      via_actions: false,
    }

    GlobalInstrumenter.instrument("package_registry.package_version_deleted", params)
  end

  def enqueue_webhook(event_type, actor_id)
    action = event_type == :published ? "create" : "update"
    input = {
      actor_id: actor_id,
      action: event_type,
      registry_package_id: self.registry_package_id,
      package_version_id: self.id,
    }

    GitHub.instrument("registry_package.#{action}", input)
    GitHub.instrument("package.#{action}", input)
  end

  def synchronize_search_index
    package&.synchronize_search_index
  end

  def strip_uri_query(uri)
    parsed = URI.parse(uri)
    parsed.scheme + "://" + parsed.host + parsed.path
  end
end
