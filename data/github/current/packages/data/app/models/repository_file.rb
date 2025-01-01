# typed: false
# frozen_string_literal: true

class RepositoryFile < ApplicationRecord::Domain::Assets
  include ::Storage::Uploadable
  include LegacyImportable

  MAX_FILE_SIZE = 25.megabytes

  set_uploadable_policy_path "repository-files"
  add_uploadable_policy_attributes :repository_id

  set_content_types \
    "application/pdf" => ".pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => ".pptx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
    "application/vnd.oasis.opendocument.text" => %w(.odt .fodt),
    "application/vnd.oasis.opendocument.spreadsheet" => %w(.ods .fods),
    "application/vnd.oasis.opendocument.presentation" => %w(.odp .fodp),
    "application/vnd.oasis.opendocument.graphics" => %w(.odg .fodg),
    "application/vnd.oasis.opendocument.formula" => ".odf",
    "application/vnd.ms-excel" => %w(.csv .xls),
    "application/zip" => ".zip",
    "application/x-zip-compressed" => ".zip",
    "application/gzip" => %w(.gz .tgz),
    "application/x-gzip" => %w(.gz .tgz),
    "text/plain" => %w(.csv .txt .patch),
    "text/x-log" => ".log",
    "text/csv" => ".csv",
    "text/comma-separated-values" => ".csv",
    "application/csv" => ".csv",
    "application/excel" => ".csv",
    "application/vnd.msexcel" => ".csv",
    "text/markdown" => ".md",
    "application/json" => %w(.json .jsonc .cpuprofile .dmp)

  belongs_to :repository
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  before_validation :infer_content_type
  belongs_to :storage_blob, class_name: "Storage::Blob"
  validate :storage_ensure_inner_asset
  validates_inclusion_of :content_type, in: allowed_content_types
  validates_presence_of :name
  validate :extension_matches_content_type
  validate :valid_file_size

  def valid_file_size
    errors.add :size, "File size too big: #{MAX_FILE_SIZE / 1.megabyte} MB are allowed, #{size / 1.megabyte} MB were attempted to upload." if size > MAX_FILE_SIZE
  end

  validate :uploader_access, on: :create
  before_destroy :storage_delete_object # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_create :choose_storage_provider # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_create :set_url_flag #rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :state, Storage::Uploadable::STATES

  include Instrumentation::Model
  def event_prefix() :repository_files end

  # BEGIN storage settings

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::MemoryAlphaPolicy
    end
    klass.new(self, actor: actor, repository: self.repository)
  end

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      repository_id: meta[:repository_id],
      name: meta[:name],
      size: meta[:size],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |file|
      file.update(state: :uploaded)
    end
  end

  alias_method :storage_blob_accessible?, :uploaded?

  def storage_transition_ready?
    repository && storage_blob_accessible?
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/repositories/#{repository_id}/files"
  end

  def storage_cluster_url(policy)
    creation_url + "/#{id}"
  end

  def storage_cluster_download_token(policy)
    super unless !GitHub.private_mode_enabled? && repository.public?
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{id}"
  end

  def storage_upload_path_info(policy)
    "/internal/storage/repositories/#{repository_id}/files"
  end

  def alambic_download_headers(options = nil)
    {
      "Content-Disposition" => "attachment;filename=#{name}",
    }
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(
      verb: :pull,
      user: actor,
      resource: repository,
    )
  end

  # s3 storage settings

  def storage_s3_key(policy)
    if storage_provider == :s3_production_data
      "#{repository_id}/#{id}"
    else
      "assets/repositories/#{repository_id}/#{id}"
    end
  end

  def storage_s3_download_query(query)
    query["response-content-disposition"] = "attachment;#{filename_content_disposition}"
    query["response-content-type"] = content_type
  end

  # END storage settings

  # Public: Absolute permalink URL for this file.
  #
  # Returns a String.
  def permalink
    if self.using_new_url
      "#{GitHub.url}/user-attachments/files/#{id}/#{CGI.escape name}"
    else
      "#{repository.permalink}/files/#{id}/#{CGI.escape name}"
    end
  end

  # The url to which we redirect requests for the permalink. The file is
  # actually stored in S3. We use permalinks to the Rails server to have a
  # consistent URL stored in issue comment bodies.
  #
  # Returns a String URL.
  def redirect_url(actor: nil)
    storage_policy(actor: actor).download_url
  end

  # Send the permalink back to the JS file uploader to include in the
  # issue comment markdown link.
  #
  # Returns a String URL.
  def url
    permalink
  end

  # Send the permalink back to the JS file uploader to include in the
  # issue comment markdown link.
  #
  # Returns a String URL.
  def storage_external_url(_ = nil)
    permalink
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def self.storage_fastly_acceleration_bucket
    "github-cloud.githubusercontent.com"
  end

  def self.storage_new_fastly_acceleration_bucket
    "github-repository-files.githubusercontent.com"
  end

  def self.memory_alpha_fastly_acceleration_bucket
    GitHub.memory_alpha_fastly_host
  end

  def self.storage_s3_new_bucket
    GitHub.s3_repository_file_new_bucket
  end

  def self.storage_s3_new_bucket_host
    GitHub.s3_repository_file_new_host
  end

  def storage_s3_bucket
    if storage_provider == :s3_production_data
      self.class.storage_s3_new_bucket
    else
      self.class.storage_s3_bucket
    end
  end

  def storage_migration_id
    name
  end

  def storage_fastly_acceleration_bucket(repository)
    if storage_provider == :s3_production_data
      self.class.storage_new_fastly_acceleration_bucket
    else
      self.class.storage_fastly_acceleration_bucket
    end
  end

  # this method is only used temporarily so we can feature flag in users. once
  # memory alpha is done testing, we can remove this method and go back to either
  # just feature flagging in repos or removing the feature flag altogether.
  def memory_alpha_fastly_acceleration_bucket(actor, repository)
    self.class.memory_alpha_fastly_acceleration_bucket
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

  def download
    instrument :download, size: size
  end

  def guid
    # We don't have a guid, but this satisfies an alambic requirement.
  end

  private

  def choose_storage_provider
    return if GitHub.storage_cluster_enabled?
    self.storage_provider = :s3_production_data
  end

  def set_url_flag
    if GitHub.flipper[:new_repository_file_url].enabled?(self.uploader)
      self.using_new_url = true
    end
  end

  def uploader_access
    if !uploader
      errors.add :uploader_id, "is not a valid User"
    elsif !repository
      errors.add :repository_id, "is not a valid repository"
    elsif !repository.pullable_by?(uploader) && !importing?
      errors.add :uploader_id, "does not have read access to #{repository.name_with_display_owner}"
    end
  end

  def filename_content_disposition
    "filename=#{name}"
  end
end
