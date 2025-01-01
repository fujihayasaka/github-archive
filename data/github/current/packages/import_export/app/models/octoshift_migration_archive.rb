# typed: true
# frozen_string_literal: true

class OctoshiftMigrationArchive < ApplicationRecord::Domain::Migrations
  include ::Storage::Uploadable
  include GitHub::Validations

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
    super unless s3_storage?
  end

  def storage_provider
    :s3_gei_archives if s3_storage?
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
    "organizations/#{organization_id}/archives/#{guid}"
  end

  private

  def s3_storage?
    return @s3_storage if defined?(@s3_storage)

    @s3_storage = GitHub.gei_archives_blob_storage_type == "s3"
  end

  def policy_class
    @policy_class ||= s3_storage? ? Storage::S3Policy : Storage::ClusterPolicy
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
