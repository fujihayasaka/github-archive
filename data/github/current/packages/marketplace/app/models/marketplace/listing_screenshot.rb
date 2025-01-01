# typed: true
# frozen_string_literal: true

class Marketplace::ListingScreenshot < ApplicationRecord::Domain::Integrations
  self.table_name = "marketplace_listing_screenshots"

  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include ::Storage::Uploadable


  SCREENSHOT_LIMIT_PER_LISTING = 5

  CAPTION_MAX_LENGTH = 150

  # Necessary to upload screenshots. See UploadPoliciesController#create.
  add_uploadable_policy_attributes :marketplace_listing_id
  set_content_types :images

  # rubocop:todo Rails/InverseOf
  belongs_to :listing, class_name: "Marketplace::Listing",
                       foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  before_validation :set_sequence

  validates :listing, :uploader, :size, presence: true
  validates :sequence, numericality: { only_integer: true }
  validates :caption, length: { maximum: CAPTION_MAX_LENGTH }
  validates :caption, unicode3: true, allow_blank: true
  validate :storage_ensure_inner_asset
  validate :uploader_access, on: :create
  validate :not_at_screenshot_limit
  validates_inclusion_of :content_type, in: allowed_content_types
  validates_presence_of :name
  validate :extension_matches_content_type
  validates_inclusion_of :size, in: 1..5.megabytes

  before_validation :set_guid, on: :create
  before_destroy :storage_delete_object_and_purge_cdn

  enum :state, Storage::Uploadable::STATES

  # BEGIN storage settings
  def self.storage_s3_bucket
    "github-#{Rails.env.downcase}-marketplace-screenshot-16aed3"
  end

  def self.storage_fastly_acceleration_bucket
    # Not configured
  end

  def storage_policy(actor: nil, repository: nil, key: nil)
    klass = if GitHub.storage_cluster_enabled?
      ::Storage::ClusterPolicy
    else
      ::Storage::S3Policy
    end
    klass.new(self, actor: actor, repository: nil)
  end

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

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |logo|
      logo.update(state: :uploaded)
    end
  end

  def alt_text
    if caption.present?
      # Screen readers will read the caption so no need to repeat it
      ""
    else
      "#{T.unsafe(listing).name} screenshot"
    end
  end

  def upload_access_grant(actor)
    Api::AccessControl.access_grant(verb: :public_site_information)
  end

  def storage_external_url(actor = nil)
    if cdn_url = GitHub.marketplace_screenshots_cdn_url
      cdn_url + storage_s3_key(policy = nil)
    else
      actor = User.ghost if actor.nil? && Rails.env.development?
      url = storage_policy(actor: actor).download_url
      if GitHub.storage_cluster_enabled? && GitHub.storage_private_mode_url
        url = url.sub(GitHub.storage_cluster_url, GitHub.storage_private_mode_url)
      end
      url
    end
  end

  def creation_url
    "#{GitHub.storage_cluster_url}/marketplace-listing-screenshots/" +
      "#{T.unsafe(listing).id}/files"
  end

  def storage_blob_accessible?
    uploaded?
  end

  def storage_upload_path_info(policy)
    "/internal/storage/marketplace-listing-screenshots/#{T.unsafe(listing).id}/files"
  end

  def storage_download_path_info(policy)
    "#{storage_upload_path_info(policy)}/#{guid}"
  end

  def storage_uploadable_attributes
    { marketplace_listing_id: T.unsafe(listing).id }
  end

  # cluster settings

  def storage_cluster_url(policy)
    "#{GitHub.storage_cluster_url}/marketplace-listing-screenshots/" +
      "#{T.unsafe(listing).id}/files/#{guid}"
  end

  # s3 storage settings

  def storage_s3_bucket
    self.class.storage_s3_bucket
  end

  def storage_fastly_acceleration_bucket(repository)
    self.class.storage_fastly_acceleration_bucket
  end

  def storage_s3_key(policy)
    "#{marketplace_listing_id}/#{guid}"
  end

  def storage_s3_access_key
    GitHub.s3_production_data_access_key
  end

  def storage_s3_secret_key
    GitHub.s3_production_data_secret_key
  end

  def storage_s3_access
    :public
  end

  def storage_s3_upload_header
    {
      "Content-Type" => content_type,
      "Cache-Control" => "max-age=2592000",
      "x-amz-meta-Surrogate-Control" => "max-age=31557600",
    }
  end

  # END storage settings

  include Instrumentation::Model

  def event_prefix
    :marketplace_listing_screenshot
  end

  # Public: Returns true if the given User has admin access to this screenshot.
  def adminable_by?(actor)
    T.unsafe(listing).adminable_by?(actor)
  end

  # Public: Resequence this screenshot in the listing's set of screenshots
  #
  # after_screenshot: the Marketplace::ListingScreenshot that should precede this one in the sequence,
  #                   or nil if this screenshot should be the first in the sequence.
  def resequence(after_screenshot:)
    new_sequence = after_screenshot ? after_screenshot.sequence : 0

    transaction do
      sequence = T.unsafe(self.sequence)
      if sequence < new_sequence
        # If the screenshot is moving right to a higher sequence number, the after_screenshot will
        # shift left/down one sequence, and this screenshot will take the after_screenshot's existing
        # sequence number.
        T.unsafe(listing).screenshots.where(sequence: (sequence + 1)..new_sequence).update_all("sequence = sequence - 1")
      elsif sequence > new_sequence
        # If the screenshot is moving left to a lower sequence number, the after_screenshot's sequence
        # won't be changing, and this screenshot will take the following sequence number - unless this
        # screenshot is moving to the front of the list, in which case all other screenshots are
        # resequenced and this screenshot takes sequence 0.
        new_sequence += 1 if after_screenshot
        T.unsafe(listing).screenshots.where(sequence: new_sequence..(sequence - 1)).update_all("sequence = sequence + 1")
      end
      update_attribute(:sequence, new_sequence)
    end
  end

  def platform_type_name
    "MarketplaceListingScreenshot"
  end

  private

  def storage_delete_object_and_purge_cdn
    storage_delete_object

    if GitHub.marketplace_screenshots_cdn_url
      PurgeFastlyUrlJob.perform_later({ "url" => storage_external_url })
    end
  end

  def uploader_access
    return unless listing

    unless T.unsafe(listing).allowed_to_edit?(uploader)
      user_desc = uploader ? uploader : "anonymous user"
      errors.add :uploader,
        "#{user_desc} does not have access to upload an image to the specified Marketplace listing"
    end
  end

  def set_sequence
    return unless listing

    self.sequence ||= T.unsafe(listing).screenshots.count
  end

  def not_at_screenshot_limit
    return unless listing

    screenshots = T.unsafe(listing).screenshots
    screenshots = screenshots.where("id <> ?", id) if persisted?

    if screenshots.count >= SCREENSHOT_LIMIT_PER_LISTING
      errors.add(:listing, "has reached its limit for screenshots")
    end
  end
end
