# typed: false
# frozen_string_literal: true

class RepositoryFile < ApplicationRecord::Domain::AssetObjects
  include ::Storage::Uploadable
  include LegacyImportable
  include Storage::FastlyRepositoryFileDependency

  MAX_FILE_SIZE = 25.megabytes

  set_uploadable_policy_path "repository-files"
  add_uploadable_policy_attributes :repository_id, :upload_container_type, :upload_container_id

  def self.baseline_content_types
    {
      # Documents
      "application/pdf" => ".pdf",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
      "application/vnd.oasis.opendocument.text" => %w(.odt .fodt),
      # Presentations
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => ".pptx",
      "application/vnd.oasis.opendocument.presentation" => %w(.odp .fodp),
      # Spreadsheets
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
      "application/vnd.oasis.opendocument.spreadsheet" => %w(.ods .fods),
      "application/vnd.ms-excel" => %w(.csv .xls),
      # Drawings/Graphics Documents
      "application/vnd.oasis.opendocument.graphics" => %w(.odg .fodg),
      "application/vnd.oasis.opendocument.formula" => ".odf",
      # Archives/Compressed
      "application/zip" => ".zip",
      "application/x-zip-compressed" => ".zip",
      "application/gzip" => %w(.gz .tgz),
      "application/x-gzip" => %w(.gz .tgz),
      # Text/Logs/Markdown
      "text/csv" => ".csv",
      "text/plain" => %w(.csv .txt .patch),
      "text/x-log" => ".log",
      "text/comma-separated-values" => ".csv",
      "application/csv" => ".csv",
      "application/excel" => ".csv",
      "application/vnd.msexcel" => ".csv",
      "text/markdown" => ".md",
      # Code/Data
      "application/json" => %w(.json .jsonc .cpuprofile .dmp),
    }
  end

  def self.expanded_content_types
    {
      # Expanded Documents
      "application/msword" => %w(.doc .rtf),
      "application/vnd.ms-outlook" => %w(.msg .eml),
      "application/vnd.ms-excel.sheet.macroEnabled.12" => %w(.xlsm),
      # Expanded Archives/Compressed
      # Expanded Text/Logs/Markdown
      "application/markdown" => %w(.copilotmd),
      "text/plain" => %w(.csv .txt .patch .debug),
      "text/tab-separated-values" => %w(.tsv),
      # Expanded Code/Data
      "application/x-yaml" => %w(.yaml .yml),
      "text/css" => %w(.css),
      "application/xml" => %w(.xml),
      "text/html" => %w(.html .htm),
      "text/javascript" => %w(.js),
      "text/typescript" => %w(.ts),
      "text/tsx" => %w(.tsx),
      "text/x-sql" => %w(.sql),
      "text/x-python" => %w(.py),
      "text/x-java-source" => %w(.java),
      "text/x-c" => %w(.c),
      "text/x-c++" => %w(.cpp),
      "application/x-ipynb+json" => %w(.ipynb),
      "text/x-shellscript" => %w(.sh),
      "text/x-php" => %w(.php),
      "text/x-csharp" => %w(.cs),
      "application/octet-stream" => %w(.pdb),
      "application/vnd.jgraph.mxfile" => %w(.drawio),
      # Expanded Images
      # Note: Currently disabled until we ensure they can be scanned: https://github.com/github/security-reviews/issues/1835
      # "image/heic" => %w(.heic),
      # "image/jpeg" => %w(.jfif),
      "image/bmp" => %w(.bmp),
      "image/tiff" => %w(.tif .tiff),
      # Expanded Audio
      "audio/mpeg" => %w(.mp3),
      "audio/wav" => %w(.wav),
    }
  end

  def self.expanded_mime_types
    {
      # XML files
      "text/xml" => %w(.xml),
      # Python files
      "text/x-python-script" => %w(.py),
      # Markdown files
      "text/x-markdown" => %w(.md),
      # Email files
      "message/rfc822" => %w(.eml),
      # Shell scripts
      "text/x-sh" => %w(.sh),
      "application/x-shellscript" => %w(.sh),
      "application/x-sh" => %w(.sh),
      # Patch files
      "text/x-patch" => %w(.patch),
      # JavaScript files
      "application/x-javascript" => %w(.js),
      # RTF files
      "text/rtf" => %w(.rtf),
      "application/rtf" => %w(.rtf),
      # SQL files
      "application/sql" => %w(.sql),
      # Java files
      "text/x-java" => %w(.java),
      # Outlook messages
      "application/vnd.ms-outlook" => %w(.msg),
      # C files
      "text/x-csrc" => %w(.c),
      # C++ files
      "text/x-c++src" => %w(.cpp),
    }
  end

  # Set baseline content types initially
  set_content_types baseline_content_types

  # The 4 methods below are used to merge the expanded file types at runtime when the issues_expanded_file_types feature flag is enabled
  # They can be removed once the feature flag is promoted after being enabled for all users.
  def self.active_content_types(actor: nil)
    content_types = baseline_content_types

    # Add expanded file types if feature flag is enabled
    if FeatureFlag.vexi.enabled?(:issues_expanded_file_types, actor, default: false)
      content_types = content_types.merge(expanded_content_types) { |_k, v1, v2| Array(v1) + Array(v2) }
    end

    # Add expanded MIME types if feature flag is enabled
    if FeatureFlag.vexi.enabled?(:expanded_mime_types_support, actor, default: false)
      content_types = content_types.merge(expanded_mime_types) { |_k, v1, v2| Array(v1) + Array(v2) }
    end

    content_types
  end
  private_class_method :active_content_types


  def self.allowed_content_types(actor: nil)
    active_content_types(actor: actor).keys
  end

  def self.content_type_for_extension(ext, actor: nil)
    active_content_types(actor: actor).find { |_ctype, exts| Array(exts).include?(ext) }&.first
  end

  def self.valid_extensions_for_content_type(content_type, actor: nil)
    Array(active_content_types(actor: actor)[content_type]).to_set
  end

  def self.user_allowed_content_extensions
    active_content_types.values.map { |v| Array(v) }.flatten.uniq.sort
  end

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf
  belongs_to :upload_container, polymorphic: true
  has_many :attachments, as: :asset, dependent: :delete_all # rubocop:todo Rails/InverseOf

  before_validation :infer_content_type
  belongs_to :storage_blob, class_name: "Storage::Blob"
  validate :storage_ensure_inner_asset
  validate :content_type_allowed
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
  before_create :set_restrict_if_unassociated_flag #rubocop:todo GitHub/AvoidActiveRecordCallbacks

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
      upload_container_type: meta[:upload_container_type],
      upload_container_id: meta[:upload_container_id],
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
    "#{repository_id}/#{id}"
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

  # Turn AssetScanner::Match objects into Repository Files to attach them to comments, wikis, etc.
  #
  # matches - Array of AssetScanner::Match objects.
  #
  # Returns an Array of RepositoryFile objects.
  def self.from_matches(matches)
    asset_ids = []
    guids = []
    matches.each do |match|
      next unless match.asset_type == "RepositoryFile"
      next unless id_string = match.asset_id
      id = id_string.to_i
      next unless id > 0
      asset_ids << id
    end

    assets = []

    ActiveRecord::Base.connected_to(role: :reading) do
      asset_ids.each_slice(100) do |slice|
        found = RepositoryFile.where(id: slice).all
        assets.push(*found) if found.present?
      end
    end

    assets.uniq!
    assets
  end

  def self.storage_s3_new_bucket
    GitHub.s3_repository_file_new_bucket
  end

  def self.storage_s3_new_bucket_host
    GitHub.s3_repository_file_new_host
  end

  def storage_s3_bucket
    self.class.storage_s3_new_bucket
  end

  def storage_migration_id
    name
  end

  def storage_s3_access_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_storage_account
    else
      GitHub.s3_production_data_access_key
    end
  end

  def storage_s3_secret_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_access_key
    else
      GitHub.s3_production_data_secret_key
    end
  end

  def download
    instrument :download, size: size
  end

  def guid
    # We don't have a guid, but this satisfies an alambic requirement.
  end

  def upload_container
    if upload_container_type == UserAsset::REPOSITORY_BLOB
      repository
    else
      super
    end
  end

  def restricted?
    attachments.empty? && restrict_if_unassociated && !can_bypass_restrictions?
  end

  def can_bypass_restrictions?
    # Note: the repository_id check is a temporary workaround to avoid restricting assets
    # that are part of the "github/release-assets" repository, whose id is 647780698
    dotcom = !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?)
    repository_id == 647780698 && dotcom
  end

  def has_access?(actor)
    if uploader&.feature_flag_enabled_or_raise?(:secured_advisory_uploads) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      if upload_container
        case upload_container
        when RepositoryAdvisory
          return upload_container.readable_by?(actor)
        end
      elsif upload_container_type
        # Handle cases where assets can be created before their accompanying container.
        case upload_container_type
        when RepositoryAdvisory.name
          return !actor.nil? && actor.respond_to?(:id) && uploader_id == actor.id
        end
      end
    end

    repository.public? || repository.readable_by?(actor)
  end

  def storage_provider
    :s3_production_data
  end

  private

  def content_type_allowed
    allowed_types = self.class.allowed_content_types(actor: uploader)
    unless allowed_types.include?(content_type)
      errors.add(:content_type, "is not included in the list of allowed content types")
    end
  end

  def infer_content_type
    if content_type.blank?
      self.content_type = self.class.content_type_for_extension(name_extension, actor: uploader)
    end
  end

  def extension_matches_content_type
    ctype_ext = self.class.valid_extensions_for_content_type(content_type.to_s, actor: uploader)
    if !ctype_ext.include?(name_extension)
      if FeatureFlag.vexi.enabled_or_raise?(:include_content_type_and_extension_in_uploadable_validation) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        errors.add :name, "has a file extension that does not match the content type: #{name_extension} != #{content_type}"
      else
        errors.add :name, "has a file extension that does not match the content type"
      end
    end
  end

  def choose_storage_provider
    self.storage_provider = :s3_production_data
  end

  def set_url_flag
    self.using_new_url = true
  end

  def set_restrict_if_unassociated_flag
    if FeatureFlag.vexi.enabled_or_raise?(:restrict_if_unassociated_assets) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      self.restrict_if_unassociated = true
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
