# typed: false
# frozen_string_literal: true

require "azure/storage/common"

class Registry::File < ApplicationRecord::Domain::Packages
  self.table_name = :package_files

  include GitHub::Relay::GlobalIdentification
  include Storage::Uploadable
  include Storage::FastlyRegistryFileDependency

  belongs_to :package_version, class_name: "Registry::PackageVersion", counter_cache: true
  after_destroy :destroy_version_if_last_file
  after_destroy :emit_destroy_event
  after_save :duplicate_version_in_mapping_table

  # rubocop:todo Rails/InverseOf
  has_many :manifest_entries,
    class_name: "Registry::ManifestEntry",
    foreign_key: :package_file_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf
  has_many :package_versions, through: :manifest_entries

  validates :md5, absence: true, if: -> { GitHub.fips_mode? }

  enum :state, Storage::Uploadable::STATES

  after_create :increment_storage_utilization

  def increment_storage_utilization
    owner_id = package_version.package.owner_id
    # azure uses gigabytes where 1 gigabyte = 1,000,000 bytes
    pkg_size = size.to_f / (1000 * 1000 * 1000).to_f

    ApplicationRecord::Domain::Packages.connection.insert(Arel.sql(<<-SQL, owner_id: owner_id, pkg_size: pkg_size))
      INSERT INTO package_storage_utilizations (owner_id, gb_used, created_at, updated_at)
      VALUES (:owner_id, :pkg_size, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        gb_used = gb_used +:pkg_size
    SQL
    GitHub.dogstats.increment "billing.package_registry.increment_storage_usage_row"
  end

  def destroy_if_orphaned
    version_file_mapping = self.manifest_entries
      # `package_version` can be `nil` here. It's not clear yet why this happens.
      # For now we treat files only pointing to `nil` package versions as orphaned.
      .select { |m| m.package_version && m.package_version.version != "docker-base-layer" }

    if version_file_mapping.any?
      last_version = version_file_mapping.last.package_version
      self.update(package_version_id: last_version.id)
    else
      destroy
    end
  end

  def self.not_found_url
    @not_found_url ||= ENV["PACKAGE_FILES_NOT_FOUND_URL"] || GitHub.urls.registry_url(:notfound)
  end

  def platform_type_name
    "PackageFile"
  end

  private

  def destroy_version_if_last_file
    with_lock do
      package_version.destroy if package_version.files.empty?
    end
  end

  def emit_destroy_event
    return if repository_id.nil?

    # Emit file deleted hydro event for registry to process
    params = {
        artifact_id: guid,
        storage_service: "AWS_S3",
        repository_id: repository_id,
    }
    GlobalInstrumenter.instrument("package_registry.package_file_destroyed", params)
  end

  def duplicate_version_in_mapping_table
    return unless package_version

    with_lock do
      sql_bindings = {
        package_file_id: id,
        package_version_id: package_version_id,
      }

      q = <<-SQL
        INSERT INTO package_version_package_files (package_file_id, package_version_id)
        VALUES (:package_file_id, :package_version_id)
        ON DUPLICATE KEY UPDATE
        package_file_id = :package_file_id,
        package_version_id = :package_version_id
      SQL
      ActiveRecord::Base.connected_to(role: :writing) do
        self.class.connection.insert(Arel.sql(q, **sql_bindings))
      end
    end
  end

  public

  belongs_to :storage_blob, class_name: "Storage::Blob"

  before_validation :set_guid, on: :create
  validate :check_maven_filename
  validates_inclusion_of :size, in: 1..2.gigabytes
  before_save :ensure_filename

  attr_writer :repository
  attr_accessor :registry_package_name
  attr_accessor :registry_package_type
  attr_accessor :version
  attr_accessor :registry_package_id
  attr_accessor :registry_package
  attr_accessor :platform

  def name
    package_type = self.registry_package_type || (self.package_version && self.package_version.package.package_type.to_s)
    package_name = self.registry_package_name || (self.package_version && self.package_version.package.name)
    platform = self.platform || (self.package_version && self.package_version.platform)
    version = self.version || (self.package_version && self.package_version.version)

    case package_type
    when "npm"
      "#{package_name}-#{version}-npm.tgz"
    when "rubygems"
      if platform.blank? || platform == "ruby"
        "#{package_name}-#{version}.gem"
      else
        "#{package_name}-#{version}-#{platform}.gem"
      end
    else
      filename
    end
  end

  def name=(val)
    @name = val
  end

  def set_guid
    self.created_at = Time.now
    self.guid ||= SimpleUUID::UUID.new(created_at).to_guid
  end

  def check_maven_filename
    package_type = self.registry_package_type || (self.registry_package && self.registry_package.package_type.to_s)
    return true unless package_type == "maven"

    # alambic sends the name of the file as `name` attribute.
    # for all our other package types, we autogenerate the filename, but for
    # maven, we have to save the filename that the client sent
    self.filename = @name if self.filename.blank?
    errors.add(:registry_package_version, "has an unspecified maven filename") if self.filename.blank?
  end

  def repository_id
    if package_version_id && package_version.nil?
      Failbot.report(StandardError.new("Missing package_version for file #{self.guid} where package_version_id:#{package_version_id} is present."))
    end

    (package_version && package_version.package&.repository_id)
  end

  def repository
    @repository || if FeatureFlag.vexi.enabled?(:repos_domain_packages, default: false)
                     Repositories.domain.by_id(repository_id)
                   else
                     Repository.find_by_id(repository_id)
                   end
  end

  def storage_policy(actor: nil, repository: nil, key: nil)
    ::Storage::S3Policy.new(self, actor: actor, repository: repository)
  end

  def ensure_filename
    self.filename ||= self.name || self.guid
  end

  def content_type
    "application/octet-stream".freeze
  end

  # cluster settings

  def storage_external_url(actor = nil)
    url = storage_policy(actor: actor, repository: repository).download_url
    if GitHub.storage_cluster_enabled? && GitHub.storage_private_mode_url
      url = url.sub(GitHub.storage_cluster_url, GitHub.storage_private_mode_url)
    end
    url
  end

  def url(actor: nil, pv: nil, owner: nil)
    pv ||= self.package_version
    owner ||= pv.package.owner
    if owner.feature_flag_enabled?(:packages_maven_registry_conditional_download_store, default: false)
      if self.object_migration_state == "complete" &&
         pv.package.package_type == "maven"
        file_key = File.join(
          pv.package.owner_id.to_s,
          pv.package.name,
          pv.version,
          self.guid
        )
        return generate_maven_sas_url(file_key)
      end
    end
    storage_policy(actor: actor, repository: repository).download_url
  end

  def metadata_url(actor: nil)
    storage_policy(actor: actor, repository: repository).metadata_url
  end

  def storage_cluster_url(policy)
    "#{GitHub.storage_cluster_url}/repository/#{self.repository_id}/registry/#{id}"
  end

  def storage_cluster_download_token(policy)
    policy.storage_cluster_download_token(policy, nil) unless !GitHub.private_mode_enabled? && package_version.package.repository.public?
  end

  def storage_download_path_info(policy)
    "/internal/storage/repository/#{self.repository_id}/registry/#{id}"
  end

  def storage_download_content_type
    "application/octet-stream"
  end

  # s3 storage settings
  def storage_s3_access_key
    if GitHub.enterprise? || Rails.env.production?
      GitHub.s3_packages_access_key || GitHub.s3_production_data_access_key
    else
      GitHub.s3_environment_config[:access_key_id]
    end
  end

  def storage_s3_secret_key
    if GitHub.enterprise? || Rails.env.production?
      GitHub.s3_packages_secret_key || GitHub.s3_production_data_secret_key
    else
      GitHub.s3_environment_config[:secret_access_key]
    end
  end

  def storage_s3_key(policy)
    "#{repository_id}/#{guid}"
  end

  def storage_s3_download_query(query)
    query["response-content-disposition"] = "filename=#{name}"
    query["response-content-type"] = "application/octet-stream"
  end

  def self.storage_s3_bucket
    GitHub.s3_packages_bucket || "github-#{Rails.env.downcase}-registry-package-file-4f11e5"
  end

  def storage_s3_bucket
    self.class.storage_s3_bucket
  end

  def storage_provider
    prov = read_attribute(:storage_provider)
    prov.blank? ? :default : prov.to_sym
  end

  def storage_s3_access
    :private
  end

  def storage_download_expiration
    5.minutes
  end

  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end


  private

  # Private methods for accessing Maven registry Azure storage account.

  # Returns the Azure::Storage::Blob::BlobService object for the Maven registry
  # storage account.
  def maven_package_registry_azure_blob_service
    if GitHub.maven_package_registry_azurite_development_storage_proxy_uri.present?
      @maven_package_registry_azure_blob_service ||= Azure::Storage::Blob::BlobService.create(
        {
          # Unfortunately `azure-storage-ruby` is **very** restrictive in
          # option sets for configuring the client. If we use
          # `use_development_storage: true` we can't pass any options other than
          # `development_storage_proxy_uri`. This is the only way to make the
          # client work with Azurite. See also https://github.com/Azure/azure-storage-ruby/blob/v1.1.0-blob/blob/lib/azure/storage/blob/blob_service.rb#L64-L75
          development_storage_proxy_uri: GitHub.maven_package_registry_azurite_development_storage_proxy_uri,
          use_development_storage: true
        }
      )
    else
      @maven_package_registry_azure_blob_service ||= Azure::Storage::Blob::BlobService.create(
        {
          default_endpoints_protocol: "https",
          storage_account_name: GitHub.maven_package_registry_azure_account_name,
          storage_access_key: GitHub.maven_package_registry_azure_account_key
        }
      )
    end
  end

  # Returns the Azure::Storage::Common::Core::Auth::SharedAccessSignature
  # object for the Maven registry storage account.
  def maven_azure_sas_generator
    @maven_azure_sas_generator ||=
      Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
        # We're using the account name config instead of the client's account
        # name to keep access consistent for Azurite in the innerloop.
        GitHub.maven_package_registry_azure_account_name,
        # The client's account key supports Azurite in the innerloop (there's a
        # magic default value) and it's using the account key config in prod.
        self.maven_package_registry_azure_blob_service.client.storage_access_key)
  end

  def generate_maven_sas_url(blob_key)
    storage_path = File.join(
      GitHub.maven_package_registry_azure_container_name,
      "blobs",
      blob_key)
    expiry = Time.now.utc + self.storage_download_expiration
    sas_token = self.maven_azure_sas_generator.generate_service_sas_token(
      storage_path,
      {
        service: "b",           # blob
        resource: "b",          # blob
        protocol: "https",
        permissions: "r",       # read-only
        expiry: expiry.to_s
      }
    )
    uri = Addressable::URI.parse(self.maven_package_registry_azure_blob_service.client.storage_blob_host)
    uri.path = storage_path
    uri.query = sas_token
    uri.to_s
  end
end
