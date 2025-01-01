# typed: false
# frozen_string_literal: true

class UploadManifestFile < ApplicationRecord::Domain::AssetObjects
  include ::Storage::Uploadable
  include GitHub::Validations
  include GitHub::Memoizer

  MAX_FILES_PER_MANIFEST = 100

  # Allow overriding value during tests.
  attr_writer :max_files_per_manifest

  set_uploadable_policy_path "upload-manifest-files"
  add_uploadable_policy_attributes :repository_id, :upload_manifest_id, :directory

  belongs_to :repository
  belongs_to :uploader, class_name: "User"
  belongs_to :manifest, class_name: "UploadManifest", foreign_key: :upload_manifest_id # rubocop:todo Rails/InverseOf
  belongs_to :storage_blob, class_name: "Storage::Blob"

  before_validation :default_content_type

  validates :uploader, presence: true
  validates :repository, presence: true
  validates :manifest, presence: true
  validates :name, presence: true
  validates_format_of :name, with: /\A[[[:graph:]] ]+\z/
  validates :directory, bytesize: { maximum: 1024 }, allow_blank: false
  validates :content_type, presence: true, length: { maximum: 255 }, unicode3: true
  validates_inclusion_of :size, in: 0..25.megabytes
  validate  :uploader_access, on: :create
  validate  :file_count_limit, on: :create
  validates_with UploadDirectoryValidator

  validates_presence_of :storage_blob, if: lambda { GitHub.storage_cluster_enabled? }
  validate :storage_ensure_inner_asset

  before_create :choose_storage_provider
  before_destroy :storage_delete_object

  enum :state, Storage::Uploadable::STATES

  # BEGIN storage settings

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    elsif GitHub.multi_tenant_enterprise?
      ::Storage::MemoryAlphaPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: self.repository)
  end

  def self.storage_new(uploader, blob, meta)
    new(
      content_type: meta[:content_type],
      directory: meta[:directory],
      name: meta[:name],
      repository_id: meta[:repository_id],
      size: meta[:size],
      storage_blob: blob,
      upload_manifest_id: meta[:upload_manifest_id],
      uploader: uploader,
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |file|
      file.update(state: :uploaded)
    end
  end

  def storage_external_url(_ = nil)
    "#{creation_url}/#{id}"
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(
      verb: :push,
      user: actor,
      resource: repository,
    )
  end

  # s3 storage settings

  def self.storage_s3_new_bucket
    GitHub.s3_upload_manifest_file_new_bucket
  end

  def self.storage_s3_new_bucket_host
    GitHub.s3_upload_manifest_file_new_host
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def self.storage_fastly_acceleration_bucket
    # Not configured
  end

  def storage_fastly_acceleration_bucket(repository)
    self.class.storage_fastly_acceleration_bucket
  end

  def storage_s3_bucket
    if storage_provider == :s3_production_data
      self.class.storage_s3_new_bucket
    else
      self.class.storage_s3_bucket
    end
  end

  def storage_s3_key(policy)
    if storage_provider == :s3_production_data
      "#{repository_id}/#{id}"
    else
      "upload-manifest-files/#{repository_id}/#{id}"
    end
  end

  def storage_s3_access_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_storage_account
    elsif storage_provider == :s3_production_data
      GitHub.s3_production_data_access_key
    else
      GitHub.s3_environment_config[:access_key_id]
    end
  end

  def storage_s3_secret_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_access_key
    elsif storage_provider == :s3_production_data
      GitHub.s3_production_data_secret_key
    else
      GitHub.s3_environment_config[:secret_access_key]
    end
  end

  # cluster settings

  def creation_url
    "#{GitHub.storage_cluster_url}/upload-manifest-files/#{upload_manifest_id}/files"
  end

  def storage_upload_path_info(policy)
    "/internal/storage/upload-manifest-files/#{upload_manifest_id}/files"
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{id}"
  end

  def storage_cluster_url(policy)
    creation_url + "/#{id}"
  end

  def storage_transition_ready?
    blob_oid.to_s.strip.blank? && storage_blob_accessible?
  end

  # END storage settings

  # Download the file contents.
  #
  # Returns the file contents.
  memoize def contents
    download
  end

  # Download and store the file in git.
  #
  # Returns the blob's git SHA String.
  def to_blob
    git = manifest.repository.rpc

    # Store the file contents as a blob.
    sha = git.write_blob(contents)
    update(blob_oid: sha)
    sha
  end

  extend GitHub::Encoding
  force_utf8_encoding :directory, :name

  def directory=(value)
    validator = UploadDirectoryValidator.new({})
    write_attribute :directory, validator.sanitize_directory_name(value)
  end

  def full_name
    path = []
    path << manifest.directory if manifest.directory.present?
    path << directory if directory.present?
    path << name
    File.join(path)
  end

  def guid
    # We don't have a guid, but this satisfies an alambic requirement.
  end

  def cleanup!
    transaction do
      GitHub::Storage::Destroyer.dereference(self)
      update_attribute(:storage_blob_id, nil)
    end
  end

  private

  def download
    uri = URI.parse(storage_policy(actor: uploader).download_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 3

    if GitHub.ssl?
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end

    response = http.get(uri.request_uri)
    if response.code == "307" && GitHub.flipper[:upload_manifest_file_download_307].enabled?(uploader)
      redirect_uri = URI.parse(response["location"])
      redirect_http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      redirect_http.open_timeout = 3
      redirect_http.read_timeout = 3

      if GitHub.ssl?
        redirect_http.use_ssl = true
        redirect_http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      response = redirect_http.get(redirect_uri.request_uri)
    end

    if response.code != "200"
      raise RuntimeError, "download error: #{response.code}"
    end

    response.body
  end

  def choose_storage_provider
    return if GitHub.storage_cluster_enabled?
    self.storage_provider = :s3_production_data
  end

  def max_files_per_manifest
    @max_files_per_manifest || MAX_FILES_PER_MANIFEST
  end

  def file_count_limit
    return unless manifest
    if manifest.files.count >= max_files_per_manifest
      errors.add :file_count, "contains too many files"
    end
  end

  def uploader_access
    if !repository
      errors.add :repository, "is required"
    elsif !manifest
      errors.add :manifest, "is required"
    elsif !repository.pushable_by?(uploader)
      errors.add :uploader, "does not have push access to this repository"
    elsif manifest.uploader != uploader
      errors.add :uploader, "does not have access to upload manifest"
    elsif !manifest.state_new?
      errors.add :manifest, "is complete and processing"
    end
  end

  # The browser sends an empty string for unknown file types. Default to a
  # generic byte stream type in that case.
  #
  # Returns nothing.
  def default_content_type
    if content_type.blank?
      self.content_type = "application/octet-stream"
    end
  end

  # Normally we sanitize these names with this method in `app/models/uploadable.rb`.
  # However with this model we reject filenames we can't deal in validation, so
  # we override this method here to do nothing instead. This allows users to keep
  # the username they wanted
  def sanitize_file_name(name)
    name
  end
end
