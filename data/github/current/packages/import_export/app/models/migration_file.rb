# typed: true
# frozen_string_literal: true

class MigrationFile < ApplicationRecord::Domain::Migrations
  include ::Storage::Uploadable
  include GitHub::Validations
  extend T::Sig

  belongs_to :migration

  before_destroy :storage_delete_object
  before_validation :set_guid, on: :create
  after_save :update_migration_archive_size

  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  validate :storage_ensure_inner_asset
  validates_presence_of :content_type, :name, :uploader
  validates :content_type, length: { maximum: 255 }, unicode3: true
  validates :name, unicode3: true

  validate :storage_ensure_asset_size

  add_uploadable_policy_attributes :migration_id, :name, :supports_multi_part_upload, :part_number, :part_sha, :multi_part_upload_id

  scope :older_than, lambda { |time| where("updated_at < ?", time) }

  enum :state, Storage::Uploadable::STATES

  # These attributes are used when the
  # uploadable is uploaded in parts via a multi-part upload.
  attr_accessor :supports_multi_part_upload, :part_number, :part_sha, :multi_part_upload_id, :repo_snapshot_owner

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      size: meta[:size],
      oid: meta[:oid],
      migration_id: meta[:migration_id],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |file|
      file.update!(state: :uploaded)
    end
  end

  # In older versions of GHES (< 3.8), Migration files are stored in cluster storage
  # and have a default purge time of 90 days. There's no reason to keep MigrationFiles this
  # long. This method overrides the default 3 month purge time down to 7 days so that customer
  # backups don't explode with extra storage usage, especially when customers run many migrations.
  def purge_at
    Time.now + 7.days
  end

  # We no longer require blobs for GHES as files are uploaded to third party
  def storage_ensure_blob
    # no-op
  end

  def storage_asset_size_range
    if is_multipart?
      T.must(T.must(migration).owner).feature_enabled?(:gh_migrator_increased_export_size) ? VALID_INCREASED_MULTIPART_SIZE_RANGE : VALID_MULTIPART_SIZE_RANGE
    else
      VALID_SIZE_RANGE
    end
  end

  def set_multi_part_attributes(state: nil, attributes: {})
    self.supports_multi_part_upload = true
    self.state = state if state.present?

    self.migration_id = attributes["migration_id"] if attributes["migration_id"]
    self.part_number = attributes["part_number"] if attributes["part_number"]
    self.part_sha = attributes["sha256"] if attributes["sha256"]

    if attributes["upload_id"]
      self.multi_part_upload_id = attributes["upload_id"]
    elsif attributes["multi_part_upload_id"]
      self.multi_part_upload_id = attributes["multi_part_upload_id"]
    end
  end

  def set_multi_part_attributes!(**args)
    set_multi_part_attributes(**args)
    save!
  end

  def storage_uploadable_attributes
    { migration_id: T.must(migration).id }
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/migrations/" +
      "#{T.must(migration).id}/archive"
  end

  def storage_upload_path_info(policy)
    "/internal/storage/migrations/#{migration_id}/archive"
  end

  def storage_policy_api_url
    "/organizations/%d/migrations/%d/archive" % [T.must(migration).owner_id, migration_id]
  end

  def storage_cluster_url(policy)
    "#{GitHub.storage_cluster_url}/migrations/" +
      "#{migration_id}/archive/#{guid}"
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{guid}"
  end

  def storage_external_url(actor = nil)
    url = storage_policy(actor: actor).download_url
    if GitHub.storage_cluster_enabled? && GitHub.storage_private_mode_url
      url = url.sub(GitHub.storage_cluster_url, GitHub.storage_private_mode_url)
    end
    url
  end

  def download_url(actor:)
    if use_azure_storage?
      exports_azure_client.generate_sas_url(self.name)
    else
      storage_policy(actor: actor).download_url
    end
  end

  def storage_policy(actor: nil, repository: nil, business: nil, key: nil)
    klass = if GitHub.migrations_blob_storage_type == "azure"
      ::Storage::AzurePolicy
    elsif GitHub.migrations_blob_storage_type == "s3"
      ::Storage::S3Policy
    elsif GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: nil)
  end

  def storage_s3_key(policy)
    case storage_provider
    when :s3_customer_migrations_data
      repository_migrations_s3_fields[:s3_key]
    when :s3_production_data
      "#{migration_id}/#{id}"
    else
      "#{GitHub.migration_file_base_path}/#{migration_id}/#{id}"
    end
  end

  def storage_s3_download_query(query)
    query["response-content-disposition"] = filename_content_disposition
    query["response-content-type"] = content_type
  end

  include Instrumentation::Model
  delegate :event_prefix, :event_payload, to: :migration

  def download
    instrument :download
  end

  def self.storage_s3_new_bucket
    "github-#{Rails.env.downcase}-migration-file-2a66d9"
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def self.storage_fastly_acceleration_bucket
    # Not configured
  end

  def filename_content_disposition
    "filename=#{T.must(migration).guid}.tar.gz"
  end

  # s3 storage settings

  def storage_s3_bucket
    case storage_provider
    when :s3_customer_migrations_data
      repository_migrations_s3_fields[:bucket]
    when :s3_production_data
      self.class.storage_s3_new_bucket
    else
      self.class.storage_s3_bucket
    end
  end

  def storage_fastly_acceleration_bucket(repository)
    self.class.storage_fastly_acceleration_bucket
  end

  def storage_s3_access_key
    case storage_provider
    when :s3_customer_migrations_data
      repository_migrations_s3_fields[:access_key]
    when :s3_production_data
      GitHub.s3_production_data_access_key
    else
      GitHub.s3_environment_config[:access_key_id]
    end
  end

  def storage_s3_secret_key
    case storage_provider
    when :s3_customer_migrations_data
      repository_migrations_s3_fields[:secret_key]
    when :s3_production_data
      GitHub.s3_production_data_secret_key
    else
      GitHub.s3_environment_config[:secret_access_key]
    end
  end

  def storage_download_expiration
    48.hours
  end

  def storage_s3_region
    return nil unless GitHub.migrations_aws_service_url.present?

    repository_migrations_s3_fields[:region]
  end

  def storage_s3_upload_header
    {
      "Content-Type" => content_type,
      "Cache-Control" => "max-age=2592000",
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
    }
  end

  # Storage client for model.
  def storage_client
    return exports_azure_client if use_azure_storage?
    return exports_s3_client if use_s3_storage?

    GitHub.s3_primary_client
  end

  def storage_provider
    if use_s3_storage?
      :s3_customer_migrations_data
    else
      super
    end
  end

  def repository_migrations_s3_fields
    uri = URI.parse(GitHub.migrations_aws_service_url)
    subdomains = T.must(uri.host).split(".")
    dirname = T.must(uri.path).delete_prefix("/")

    key = File.join([dirname, name].compact_blank)

    # service url is looks like https://s3.us-east-1.amazonaws.com subdomains[1] will be region
    {
      bucket: GitHub.migrations_s3_bucket,
      s3_key: key,
      region: T.must(subdomains)[1] == "amazonaws" ? "us-east-1" : T.must(subdomains)[1],
      access_key: GitHub.migrations_aws_access_key,
      secret_key: GitHub.migrations_aws_secret_key,
    }
  end

  def exports_azure_client
    @exports_azure_client ||= GitHub::AzureSnapshotUploader.new(
      container_name: "migration-archives",
      storage_connection_string: GitHub.migrations_azure_connection_string,
      use_connection_string: true
    )
  end

  def exports_s3_client
    @exports_s3_client ||= Aws::S3::Client.new(
      access_key_id: repository_migrations_s3_fields[:access_key],
      secret_access_key: repository_migrations_s3_fields[:secret_key],
      region: repository_migrations_s3_fields[:region],
      http_proxy: GitHub.enterprise? ? GitHub.http_proxy_config : nil
    )
  end

  def use_azure_storage?
    GitHub.enterprise? && GitHub.migrations_blob_storage_type == "azure" && GitHub.migrations_azure_connection_string.present?
  end

  def use_s3_storage?
    GitHub.enterprise? && GitHub.migrations_blob_storage_type == "s3" && GitHub.migrations_aws_secret_key.present?
  end

  private

  def update_migration_archive_size
    migration&.update_column :archive_size, size

    # This method shouldn't prevent a MigrationFile from saving or break the
    # callback chain
    # https://apidock.com/rails/ActiveRecord/Callbacks/after_save#656-Return-True
    true
  end

  sig { void }
  def validate_migration
    raise "Invalid migration" unless migration.is_a?(Migration)
  end
end
