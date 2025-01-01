# typed: true
# frozen_string_literal: true

class OctoshiftMigrationArchive < ApplicationRecord::Domain::Migrations
  include ::Storage::Uploadable
  include GitHub::Validations

  S3_STORAGE_PROVIDER = :s3_gei_archives
  AZURE_STORAGE_PROVIDER = :azure_gei_archives
  CLUSTER_STORAGE_PROVIDER = :cluster_gei_archives

  DOWNLOAD_URL_EXPIRE_TIME = 2.hours

  FEATURE_FLAG_USE_AZURE = "octoshift_ops__github_owned_storage_use_azure"
  FEATURE_FLAG_ENABLE_AZURE_SUPPORT = "octoshift_ops__github_owned_storage_enable_azure_support"

  belongs_to :organization
  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  validate :storage_ensure_inner_asset
  validates_presence_of :name, :content_type, :uploader, :organization
  validates :content_type, length: { maximum: 255 }, unicode3: true
  validates :name, unicode3: true
  validate :storage_ensure_asset_size

  before_validation :set_guid, on: :create
  before_destroy :storage_delete_object
  before_create :choose_storage_provider, if: :azure_support_enabled?
  after_create :emit_storage_metrics_create
  after_destroy :emit_storage_metrics_destroy

  add_uploadable_policy_attributes :name, :organization_id, :supports_multi_part_upload, :part_number, :part_sha, :multi_part_upload_id

  enum :state, Storage::Uploadable::STATES

  attr_accessor :supports_multi_part_upload, :part_number, :part_sha, :multi_part_upload_id

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      size: meta[:size],
      oid: meta[:oid],
      organization_id: meta[:organization_id]
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |octoshift_migration_archive|
      octoshift_migration_archive.update!(state: :uploaded)
    end
  end

  def platform_type_name
    "MigrationArchive"
  end

  def global_id
    guid
  end

  def set_multi_part_attributes(state:, attributes:)
    self.supports_multi_part_upload = true
    self.state = state
    self.part_number = attributes["part_number"]
    self.part_sha = attributes["sha256"]
    self.multi_part_upload_id = attributes["upload_id"] || attributes["multi_part_upload_id"]
  end

  def set_multi_part_attributes!(state:, attributes:)
    set_multi_part_attributes(state: state, attributes: attributes)

    save!
  end

  def gei_uri
    "gei://archive/#{guid}"
  end

  def storage_policy(actor: nil, repository: nil, business: nil, key: nil)
    policy_class.new(self, actor: actor, repository: nil)
  end

  def storage_external_url(actor = nil)
    url = storage_policy(actor: actor).download_url

    if GitHub.storage_cluster_enabled? && GitHub.storage_private_mode_url
      url = url.sub(GitHub.storage_cluster_url, GitHub.storage_private_mode_url)
    end

    url
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/organizations/#{organization_id}/gei/archive"
  end

  def storage_upload_path_info(_policy)
    "/internal/storage/organizations/#{organization_id}/gei/archive"
  end

  def storage_policy_api_url
    "/organizations/#{organization_id}/gei/archive/#{guid}"
  end

  def storage_cluster_url(_policy)
    "#{GitHub.storage_cluster_url}/organizations/#{organization_id}/gei/archive/#{guid}"
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{guid}"
  end

  def download_url(actor:)
    storage_policy(actor: actor).download_url
  end

  def storage_ensure_blob
    if azure_support_enabled?
      super if blob_required?
    else
      super unless s3_storage?
    end
  end

  def storage_provider
    if azure_support_enabled?
      # storage_provider is a column on OctoshiftMigrationArchive that keeps track of the storage provider, which is
      # currently S3, Azure, or cluster storage (for development and testing).  Prior to
      # https://github.com/github/github/pull/390344, this field was always nil, which is transformed to :default via
      # Storage::Uploadable::Policy#storage_provider.
      #
      # Thankfully, all records are automatically deleted after 7 days, and as of this writing, all nil records in
      # production are for S3 storage.  This means that we can trust any new values from storage_provider fields, fall
      # back to assuming S3 for nil values in production, and assume cluster storage when it's enabled.
      #
      # Eventually, all the nil records will be automatically deleted, and only set values will be in the database.  When
      # we're at this point, we can remove this entire #storage_provider method, as this currently overrides the
      # ActiveRecord getter for this field.  We could write a transition for this, but since the transitioned data will
      # only last a maximum of 7 days, this backward-compatible code accomplishes the same end result.
      #
      # After octoshift_ops__github_owned_storage_use_azure has been 100% shipped, we're confident about using Azure
      # storage without a FF fallback, and all S3-backed records have expired, we can remove this method entirely and
      # rely on the storage_provider column's value for all records.

      return @storage_provider if defined?(@storage_provider)

      @storage_provider = case
      when super != :default
        super
      when GitHub.storage_cluster_enabled?
        CLUSTER_STORAGE_PROVIDER
      else
        S3_STORAGE_PROVIDER
      end
    else
      :s3_gei_archives if s3_storage?
    end
  end

  def storage_abs_container
    GitHub.gei_archives_storage_abs_container
  end

  def storage_abs_key(_policy)
    storage_key
  end

  def abs_storage_account_name
    GitHub.gei_archives_abs_storage_account_name
  end

  def abs_spn_tenant_id
    GitHub.gei_archives_abs_spn_tenant_id
  end

  def abs_spn_client_id
    GitHub.gei_archives_abs_spn_client_id
  end

  def abs_spn_client_secret
    GitHub.gei_archives_abs_spn_client_secret
  end

  def storage_s3_access_key
    GitHub.gei_archives_aws_access_key_id
  end

  def storage_s3_secret_key
    GitHub.gei_archives_aws_secret_access_key
  end

  def storage_s3_bucket
    "github-#{Rails.env.downcase}-gei-archive-23d850"
  end

  def storage_s3_key(_policy)
    storage_key
  end

  def storage_download_expiration
    return DOWNLOAD_URL_EXPIRE_TIME if FeatureFlag.vexi.enabled?(:octoshift_ops__github_owned_storage_2h_link_expiration, default: true)

    super
  end

  private

  def default_to_azure?
    FeatureFlag.vexi.enabled?(FEATURE_FLAG_USE_AZURE, organization, default: false)
  end

  def azure_support_enabled?
    FeatureFlag.vexi.enabled?(FEATURE_FLAG_ENABLE_AZURE_SUPPORT, organization, default: false)
  end

  def choose_storage_provider
    self.storage_provider = case
    when default_to_azure? || GitHub.gei_archives_blob_storage_type == "azure"
      AZURE_STORAGE_PROVIDER
    when GitHub.gei_archives_blob_storage_type == "s3"
      S3_STORAGE_PROVIDER
    else
      CLUSTER_STORAGE_PROVIDER
    end
  end

  def policy_class
    @policy_class ||= case storage_provider
    when S3_STORAGE_PROVIDER
      Storage::S3Policy
    when AZURE_STORAGE_PROVIDER
      Storage::AzurePolicy
    else
      Storage::ClusterPolicy
    end
  end

  def s3_storage?
    return @s3_storage if defined?(@s3_storage)

    @s3_storage = GitHub.gei_archives_blob_storage_type == "s3"
  end

  def blob_required?
    return @blob_required if defined?(@blob_required)

    @blob_required = policy_class == Storage::ClusterPolicy
  end

  def storage_key
    "organizations/#{organization_id}/archives/#{guid}"
  end

  def emit_storage_metrics_create
    GitHub.dogstats.increment(
      "gh.migration_tools.octoshift_migration_archive.create.increment",
      tags: ["org_id:#{organization_id}"]
    )

    GitHub.dogstats.count(
      "gh.migration_tools.octoshift_migration_archive.create.count",
      size,
      tags: ["org_id:#{organization_id}"]
    )
  end

  def emit_storage_metrics_destroy
    GitHub.dogstats.increment(
      "gh.migration_tools.octoshift_migration_archive.destroy.increment",
      tags: ["org_id:#{organization_id}"]
    )

    GitHub.dogstats.count(
      "gh.migration_tools.octoshift_migration_archive.destroy.count",
      size,
      tags: ["org_id:#{organization_id}"]
    )
  end
end
