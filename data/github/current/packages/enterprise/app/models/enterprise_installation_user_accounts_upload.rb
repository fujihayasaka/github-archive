# typed: true
# frozen_string_literal: true

# Represents the upload of a user accounts JSON file exported from an Enterprise
# Server installation.
#
# Belongs to a single Enterprise Server installation.
class EnterpriseInstallationUserAccountsUpload < ApplicationRecord::Collab
  # Needed for uploading files. See UploadPoliciesController#create.
  MAX_SIZE_MEGABYTES = 25

  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include ::Storage::Uploadable

  # Associate directly with a business, as it is possible that no
  # EnterpriseInstallation exists, and that the upload will _create_ a new
  # EnterpriseInstallation belonging to the business.
  belongs_to :business

  # Not a required association initially. An upload will first belong to a
  # Business, after which a sync will be enqueued, which will attempt to either
  # create a new EnterpriseInstallation for the upload or associate the upload
  # with an existing upload belonging to the Business.
  belongs_to :enterprise_installation

  before_create :choose_storage_provider
  before_destroy :storage_delete_object
  before_validation :set_guid, on: :create

  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  validates :business, :content_type, :name, presence: true
  validate :ensure_enterprise_installation_owned_by_business
  validate :storage_ensure_inner_asset
  validate :storage_ensure_asset_size
  validates_inclusion_of :size, in: 1..MAX_SIZE_MEGABYTES.megabytes

  validates :name, unicode3: true

  set_uploadable_policy_path :enterprise_installation_user_accounts_uploads
  add_uploadable_policy_attributes :business_id, :enterprise_installation_id, :name

  set_content_types "application/json" => ".json"
  validates_inclusion_of :content_type, in: allowed_content_types

  enum :state, Storage::Uploadable::STATES

  enum :sync_state, {
    pending: 0,
    success: 1,
    failure: 2,
  }, prefix: :sync

  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      size: meta[:size],
      oid: meta[:oid],
      business_id: meta[:business_id],
      enterprise_installation_id: meta[:enterprise_installation_id],
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |upload|
      upload.update!(state: :uploaded)
    end
  end

  def storage_uploadable_attributes
    atts = { business_id: business_id }
    if enterprise_installation_id.present?
      atts[:enterprise_installation_id] = enterprise_installation_id
    end
    atts
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/businesses/#{T.must(business).slug}/user-accounts-uploads"
  end

  def storage_upload_path_info(policy)
    "/internal/storage/businesses/#{T.must(business).slug}/user-accounts-uploads"
  end

  def storage_policy_api_url
    "/businesses/%s/user-accounts-uploads/%d" % [T.must(business).slug, id]
  end

  def storage_cluster_url(policy)
    "#{creation_url}/#{guid}"
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
    storage_policy(actor: actor).download_url
  end

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    elsif GitHub.multi_tenant_enterprise?
      ::Storage::MemoryAlphaPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: nil)
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(
      verb: :write_business_enterprise_installation_user_accounts,
      user: actor,
      resource: business,
    )
  end

  def storage_s3_key(policy)
    if T.cast(storage_provider, Symbol) == :s3_production_data
      "#{T.must(business).slug}/#{guid}"
    else
      "businesses/#{T.must(business).slug}/#{guid}"
    end
  end

  def storage_s3_download_query(query)
    query["response-content-disposition"] = filename_content_disposition
    query["response-content-type"] = content_type
  end

  def self.storage_s3_new_bucket
    "github-#{Rails.env.downcase}-enterprise-accounts-upload-3bde4e"
  end

  def self.storage_s3_bucket
    GitHub.s3_environment_config[:asset_bucket_name]
  end

  def filename_content_disposition
    "filename=#{name}"
  end

  # S3 storage settings

  def storage_s3_bucket
    if T.cast(storage_provider, Symbol) == :s3_production_data
      self.class.storage_s3_new_bucket
    else
      self.class.storage_s3_bucket
    end
  end

  def storage_s3_access_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_storage_account
    elsif T.cast(storage_provider, Symbol) == :s3_production_data
      GitHub.s3_production_data_access_key
    else
      GitHub.s3_environment_config[:access_key_id]
    end
  end

  def storage_s3_secret_key
    if GitHub.multi_tenant_enterprise?
      GitHub.uploadable_access_key
    elsif T.cast(storage_provider, Symbol) == :s3_production_data
      GitHub.s3_production_data_secret_key
    else
      GitHub.s3_environment_config[:secret_access_key]
    end
  end

  def storage_s3_upload_header
    {
      "Content-Type" => content_type,
      "Cache-Control" => "max-age=2592000",
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
    }
  end

  # Public: Download the blob and read the return the blob contents as a String.
  #
  # actor - The User reading the blob.
  #
  # Returns a String containing the file contents.
  def download_and_read_file(actor:)
    T.must(T.unsafe(URI(download_url(actor: actor))).open).read
  end

  def platform_type_name
    "EnterpriseServerUserAccountsUpload"
  end

  private

  def ensure_enterprise_installation_owned_by_business
    return unless self.enterprise_installation.present?
    return if T.must(self.enterprise_installation).owner == business
    errors.add(:enterprise_installation, "must belong to the business to which the download belongs")
  end

  def choose_storage_provider
    return if GitHub.storage_cluster_enabled?
    if GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:enterprise_license_s3_production_data, business, default: false)
      self.storage_provider = "s3_production_data"
    end
  end
end
