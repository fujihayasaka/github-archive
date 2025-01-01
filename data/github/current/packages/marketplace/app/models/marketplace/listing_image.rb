# typed: strict
# frozen_string_literal: true

class Marketplace::ListingImage < ApplicationRecord::Domain::Integrations
  self.table_name = "marketplace_listing_images"

  include GitHub::Relay::GlobalIdentification
  include ::Storage::Uploadable


  # Necessary to upload images. See UploadPoliciesController#create.
  add_uploadable_policy_attributes :marketplace_listing_id
  set_content_types :images

  # rubocop:todo Rails/InverseOf
  belongs_to :listing, class_name: "Marketplace::Listing",
                       foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  validates :listing, :uploader, :size, presence: true
  validate :storage_ensure_inner_asset
  validate :uploader_access, on: :create
  validates_inclusion_of :content_type, in: allowed_content_types
  validates_presence_of :name
  validate :extension_matches_content_type
  validates_inclusion_of :size, in: 1..1.megabytes

  before_validation :set_guid, on: :create
  before_destroy :storage_delete_object_and_purge_cdn

  enum :state, Storage::Uploadable::STATES

  # BEGIN storage settings
  sig { returns(String) }
  def self.storage_s3_bucket
    "github-#{Rails.env.downcase}-marketplace-image-7cfaf6"
  end

  sig do
    params(actor: T.nilable(User), repository: T.nilable(Repository), key: T.nilable(String))
      .returns(T.any(Storage::ClusterPolicy, Storage::S3Policy))
  end
  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: nil)
  end

  sig { params(uploader: User, blob: Storage::Blob, meta: T::Hash[Symbol, T.untyped]).returns(Marketplace::ListingImage) }
  def self.storage_new(uploader, blob, meta)
    new(
      storage_blob: blob,
      uploader: uploader,
      content_type: meta[:content_type],
      name: meta[:name],
      size: meta[:size],
      marketplace_listing_id: meta[:marketplace_listing_id],
    )
  end

  sig { params(uploader: User, blob: Storage::Blob, meta: T::Hash[Symbol, T.untyped]).void }
  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |image|
      image.update(state: :uploaded)
    end
  end

  sig { params(actor: T.nilable(User)).returns(T.untyped) }
  def upload_access_grant(actor)
    Api::AccessControl.access_grant(verb: :public_site_information)
  end

  sig { params(actor: T.nilable(User)).returns(String) }
  def storage_external_url(actor = nil)
    if cdn_url = GitHub.marketplace_images_cdn_url
      cdn_url + storage_s3_key(policy = nil)
    else
      url = storage_policy(actor: actor).download_url
      if GitHub.storage_cluster_enabled? && GitHub.storage_private_mode_url
        url = url.sub(GitHub.storage_cluster_url, GitHub.storage_private_mode_url)
      end
      url
    end
  end

  sig { params(viewer: T.nilable(User)).returns(String) }
  def hero_image_url(viewer)
    url = Addressable::URI.parse(storage_external_url(viewer))

    image_params = { width: 600, format: "jpeg", auto: "webp" }
    url.query_values = (url.query_values || {}).merge(image_params)

    url.to_s
  end

  sig { returns(String) }
  def creation_url
    "#{GitHub.storage_cluster_url}/marketplace-listing-images/" +
      "#{listing&.id}/files"
  end

  sig { returns(T::Boolean) }
  def storage_blob_accessible?
    uploaded?
  end

  sig { params(policy: T.untyped).returns(String) }
  def storage_upload_path_info(policy)
    "/internal/storage/marketplace-listing-images/#{listing&.id}/files"
  end

  sig { params(policy: T.untyped).returns(String) }
  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{guid}"
  end

  sig { returns(T::Hash[Symbol, T.nilable(Integer)]) }
  def storage_uploadable_attributes
    { marketplace_listing_id: listing&.id }
  end

  # cluster settings
  sig { params(policy: T.untyped).returns(String) }
  def storage_cluster_url(policy)
    "#{GitHub.storage_cluster_url}/marketplace-listing-images/" +
      "#{listing&.id}/files/#{guid}"
  end

  # s3 storage settings
  sig { returns(String) }
  def storage_s3_bucket
    self.class.storage_s3_bucket
  end

  sig { params(policy: T.untyped).returns(String) }
  def storage_s3_key(policy)
    "#{marketplace_listing_id}/#{guid}"
  end

  sig { returns(T.nilable(String)) }
  def storage_s3_access_key
    GitHub.s3_production_data_access_key
  end

  sig { returns(T.nilable(String)) }
  def storage_s3_secret_key
    GitHub.s3_production_data_secret_key
  end

  sig { returns(Symbol) }
  def storage_s3_access
    :public
  end

  sig { returns(T::Hash[String, String]) }
  def storage_s3_upload_header
    {
      "Content-Type" => content_type,
      "Cache-Control" => "max-age=2592000",
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
    }
  end

  # END storage settings

  include Instrumentation::Model

  sig { returns(Symbol) }
  def event_prefix
    :marketplace_listing_image
  end

  # Public: Returns true if the given User has edit access to this image.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def editable_by?(actor)
    # TODO: Can likely remove this
    T.unsafe(listing).editable_by?(actor)
  end

  private

  sig { void }
  def storage_delete_object_and_purge_cdn
    storage_delete_object

    if GitHub.marketplace_images_cdn_url
      PurgeFastlyUrlJob.perform_later({ "url" => storage_external_url })
    end
  end

  sig { void }
  def uploader_access
    return unless listing

    unless T.unsafe(listing).allowed_to_edit?(uploader)
      user_desc = uploader ? uploader : "anonymous user"
      errors.add :uploader,
        "#{user_desc} does not have access to upload an image to the specified Marketplace listing"
    end
  end
end
