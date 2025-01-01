# typed: false
# frozen_string_literal: true

# Joins an owner (User, Org, Business, etc) to an asset that contains their avatar.
# Multiple avatars for an owner can be stored.  See PrimaryAvatar for the
# owner's one true avatar.
class Avatar < ApplicationRecord::Domain::Users
  # storage settings are in Avatar::Shared
  include ::Storage::Uploadable
  include AssetUploadable
  include Instrumentation::Model

  VALID_OWNER_TYPES = %w(
    Integration
    Marketplace::Listing
    RepositoryAction
    OauthApplication
    Team
    Business
    User
  )

  uploadable_policy_attributes.delete(:name)
  uploadable_policy_attributes << :organization_id
  uploadable_policy_attributes << :owner_id
  uploadable_policy_attributes << :owner_type
  set_content_types :images

  has_one :primary_avatar
  belongs_to :owner, -> { including_deleted }, polymorphic: true
  belongs_to :storage_blob, class_name: "Storage::Blob"
  belongs_to :asset
  belongs_to :uploader, class_name: "User", foreign_key: :uploader_id # rubocop:todo Rails/InverseOf

  validate :storage_ensure_inner_asset
  validates_presence_of :owner, :uploader
  validates_uniqueness_of :asset_id, scope: [:owner_id, :owner_type], if: lambda { !GitHub.storage_cluster_enabled? }
  validates_inclusion_of :size, in: 1..1.megabyte
  validates_inclusion_of :owner_type, in: VALID_OWNER_TYPES
  validate :uploader_can_upload
  validate :ensure_image_size
  validates_inclusion_of :content_type, in: allowed_content_types

  after_destroy :set_primary_avatar
  after_commit :update_keys_in_cdn, on: :update
  after_commit :purge_keys_from_cdn, on: :destroy
  after_commit :instrument_destroy, on: :destroy
  after_destroy :dereference_asset
  after_destroy :storage_remove_from_cluster

  def self.fetch(owner, oid)
    where(
      "id" => Asset.joins(:references).where("oid = ? AND uploadable_type = 'Avatar'", oid).pluck("uploadable_id"),
      "owner_type" => owner.class.base_class.name,
      "owner_id"   => owner.id,
    ).first
  end

  def self.upload(uploader, oid, meta)
    owner = owner_for(nil, meta)
    avatar = fetch(owner, oid)
    Asset.upload(avatar, oid, meta) do |asset|
      create!(asset: asset, uploader: uploader, owner: owner, content_type: meta[:content_type])
    end
  end

  def self.build_for_asset_validation(uploader, meta)
    new(uploader: uploader, owner: owner_for(nil, meta), content_type: meta[:content_type])
  end

  def self.owner_for(_, meta)
    klass = valid_owner_klass_for_type(meta[:owner_type])
    klass.try(:find_by_id, meta[:owner_id].to_i)
  end

  def self.valid_owner_klass_for_type(type)
    return unless VALID_OWNER_TYPES.include?(type)
    type.constantize
  end

  def self.valid_owner_type_sentence
    Avatar::VALID_OWNER_TYPES.to_sentence(
      two_words_connector: " or ",
      last_word_connector: " or ",
    )
  end

  def target_for_conditional_access
    owner.target_for_conditional_access
  end

  def width
    if GitHub.storage_cluster_enabled?
      read_attribute(:width)
    else
      asset || raise(GitHub::DataQualityError.new(self, :asset))
      asset.width
    end
  end

  def height
    if GitHub.storage_cluster_enabled?
      read_attribute(:height)
    else
      asset || raise(GitHub::DataQualityError.new(self, :asset))
      asset.height
    end
  end

  def avatar_oid
    oid
  end

  ACCEPTED_METADATA = [:content_type, :cropped_x, :cropped_y, :cropped_width, :cropped_height]

  # Public: Updates the asset's meta data.  See Asset#update_meta.
  def update_meta(meta)
    asset.update_meta(meta)
    saving = false
    ACCEPTED_METADATA.each do |attrib|
      next unless value = meta[attrib]
      saving = true
      send("#{attrib}=", value)
    end
    save! if saving
  end

  def editable_by?(user)
    return false if owner.nil? || user.nil?
    return false if !user.user? && !user.organization?
    owner.avatar_editable_by?(user)
  end

  def set_primary_avatar
    return unless primary = primary_avatar
    if new_avatar = replacement_primary_avatar_candidate
      PrimaryAvatar.set!(new_avatar, new_avatar.uploader)
    else
      primary.destroy
    end
  end

  def replacement_primary_avatar_candidate
    return unless owner

    owner.avatars.detect { |avatar| owner.avatar_editable_by?(avatar.uploader) }
  end

  def content_type
    encode_to_png? ? "image/png" : super
  end

  def updated_at
    self[:updated_at] || self[:created_at]
  end

  def creation_url
    if GitHub.storage_cluster_enabled?
      "#{GitHub.storage_cluster_url}/avatars"
    else
      "#{GitHub.alambic_uploads_url}/avatars"
    end
  end

  def needs_crop?
    !cropped? && width != height
  end

  def can_upload?
    owner && uploader && owner.avatar_editable_by?(uploader)
  end

  def uploader_can_upload
    return if can_upload?
    errors.add(:uploader_id, "does not have access to change this avatar.")
  end

  def invalid_image_dimension?(length)
    length.zero? || length > 3000
  end

  def ensure_image_size
    if invalid_image_dimension?(width.to_i) || invalid_image_dimension?(height.to_i)
      error_target = GitHub.storage_cluster_enabled? ? :base : :asset_id
      errors.add(error_target, "Has invalid dimensons: #{width.to_i}x#{height.to_i}")
    end

    if needs_crop?
      ensure_auto_cropped_coordinates
    else
      ensure_cropped_coordinates
    end
  end

  def ensure_auto_cropped_coordinates
    if width > height
      self.cropped_width = self.cropped_height = height
      self.cropped_y = 0
      self.cropped_x = (width - height) / 2
    else
      self.cropped_width = self.cropped_height = width
      self.cropped_x = 0
      self.cropped_y = (height - width) / 2
    end
  end

  def ensure_cropped_coordinates
    w = width.to_i
    h = height.to_i

    cropped_w = cropped_width.to_i
    cropped_h = cropped_height.to_i
    self.cropped_x = [0, cropped_x.to_i].max # make sure it's >= 0
    self.cropped_y = [0, cropped_y.to_i].max

    cropped_x2 = cropped_x + cropped_w
    if cropped_x2 > w
      self.cropped_width = cropped_w = cropped_w - (cropped_x2 - w)
    end

    cropped_y2 = cropped_y + cropped_h
    if cropped_y2 > h
      self.cropped_height = cropped_h = cropped_h - (cropped_y2 - h)
    end

    # make sure crop region is a square
    self.cropped_width = self.cropped_height = [cropped_w, cropped_h].min

    if cropped_x + cropped_w > w
      errors.add(:cropped_width, "is larger than the image width")
    end

    if cropped_y + cropped_h > h
      errors.add(:cropped_height, "is larger than the image height")
    end
  end

  def scaled_width(max_width)
    width.to_i > max_width ? max_width : width.to_i
  end

  def scaled_height(max_width)
    width.to_i > max_width ? (max_width * (height.to_f / width.to_i)).round : height.to_i
  end

  def archive?(asset)
    return false unless asset.id == asset_id
    asset.references.where(uploadable_type: self.class.base_class.name).first.nil?
  end

  def self.storage_s3_bucket
    "github-#{Rails.env.downcase}-avatar-1823e5"
  end

  def self.storage_fastly_acceleration_bucket
    # Not configured
  end

  def storage_s3_bucket
    self.class.storage_s3_bucket
  end

  # Repository will here be always nil, but needed for
  # feature flag for now and will be cleaned up.
  def storage_fastly_acceleration_bucket(repository)
    self.class.storage_fastly_acceleration_bucket
  end

  def storage_s3_key(policy)
    "#{owner_type}/#{owner_id}/#{id}"
  end

  def storage_s3_access_key
    GitHub.s3_production_data_access_key
  end

  def storage_s3_secret_key
    GitHub.s3_production_data_secret_key
  end

  def self.storage_new(uploader, blob, meta)
    owner_type = meta[:owner_type]
    owner_id = meta[:owner_id]
    if owner = meta[:owner]
      owner_type = owner.class.base_class.name
      owner_id = owner.id
    end

    new(
      storage_blob: blob,
      uploader: uploader,
      owner_type: owner_type,
      owner_id: owner_id,
      content_type: meta[:content_type],
      width: 100,
      height: 100,
    )
  end

  def self.storage_create(uploader, blob, meta)
    storage_new(uploader, blob, meta).tap do |av|
      av.update(
        width: meta[:width],
        height: meta[:height],
      )
    end
  end

  # Shared with Avatar and PrimaryAvatar
  module Shared
    def self.included(model)
      super
      model.send :attr_accessor, :alambic_use_original_filter
      model.send :attr_accessor, :alambic_size_filter
    end

    # earliest Avatar ID that has run through graphicsmagick
    EARLIEST_FILTERED_ID = if Rails.env.test?
      100_000
    elsif Rails.env.production? && !GitHub.enterprise?
      81650
    else
      0
    end

    include AssetUploadable::Purgeable

    # BEGIN storage settings

    def storage_policy(actor: nil, repository: nil, key: nil)
      if storage_provider == :s3_production_data
        # TODO: remove this, avatars are alambic
        # https://github.com/github/github/pull/187585#discussion_r679394265
        ::Storage::S3Policy.new(self, actor: actor)
      elsif GitHub.storage_cluster_enabled?
        ::Storage::ClusterPolicy.new(self, actor: actor)
      else
        ::Storage::AlambicPolicy.new(self, actor: actor)
      end
    end

    def upload_access_grant(actor)
      Api::AccessControl.access_grant(
        verb: :create_avatar,
        owner: owner,
        user: actor,
      )
    end

    # alambic storage settings

    def storage_alambic_url(policy)
      "#{GitHub.alambic_assets_url}/#{avatar_surrogate_key}"
    end

    # cluster storage settings

    def storage_cluster_url(policy)
      "#{GitHub.storage_cluster_url}/#{avatar_surrogate_key}"
    end

    def storage_cluster_download_token(policy)
      return unless policy.actor

      self.class.storage_auth_token(policy.actor,
        { path_info: storage_download_path_info(policy) }
      )
    end

    def storage_blob_accessible?
      true
    end

    def storage_upload_path_info(policy = nil)
      "/internal/storage/avatars"
    end

    def storage_download_path_info(policy = nil)
      "#{storage_upload_path_info(policy)}/#{id}"
    end

    def storage_external_url(actor = nil)
      return unless GitHub.storage_cluster_enabled?
      url = storage_policy(actor: actor).download_url
      url = url.sub(GitHub.storage_cluster_url, GitHub.storage_private_mode_url) if  GitHub.storage_private_mode_url
      url
    end

    def storage_uploadable_attributes
      {
        owner_type: owner_type,
        owner_id: owner_id,
      }
    end

    # END storage settings

    ## FILTERS

    # Public: Describes the filters that are run when images are uploaded.
    def alambic_upload_filters
      # Only use sampling when processing pngs, to avoid negative side effects,
      # http://www.imagemagick.org/Usage/resize/#sample, when possible.
      resize_method = content_type == "image/png" ? :sample : :resize

      {
        original: [
          {
            command: :filesig,
            params: {
              filesig_guess: "png,jpg,gif",
            },
          },
          {
            command: :imagemagick,
            params: {
              :max_width => "10000",
              :max_height => "10000",
              resize_method => "1000x1000>",
              :strip => :exif,
              :orient => :auto,
              :flatten => :animations,
            },
          },
        ],
      }

    end

    # Public: Lists the headers that should be part of every avatar download
    # response.
    def alambic_download_headers(options = nil)
      {
        "Surrogate-Key" => surrogate_key,
        "Surrogate-Control" => "max-age=31557600",
        "Cache-Control" => "max-age=300",
      }
    end

    # Public: Describe the filters that are run when avatars are downloaded.
    def alambic_download_filters
      if filter = alambic_image_filter
        { original: [filter] }
      end
    end

    # Internal: Describes the image filter for this avatar, if needed.
    def alambic_image_filter
      params = {}

      if encode_to_png?
        params[:encode] = :png
      end

      if cropped? && !@alambic_use_original_filter
        params[:crop] = cropped_dimensions
      end

      size = @alambic_size_filter.to_i
      if size > 0 && !@alambic_use_original_filter
        params[:resize] = "#{size},#{size}"
      end

      if params.blank?
        return
      end

      { command: :image, params: params }
    end

    # Builds the query string for the internal media:/ uri to filter this
    # avatar as it's downloaded.
    def alambic_internal_media_querystring
      alambic_internal_media_query.to_query
    end

    def alambic_internal_media_query
      hash = {
        type: content_type,
        last_mod: updated_at.to_i,
      }

      if encode_to_png?
        hash["filter[image.encode]"] = "png"
      end

      if cropped? && !@alambic_use_original_filter
        hash["filter[image.crop]"] = cropped_dimensions
      end

      hash
    end

    def encode_to_png?
      !new_record? && avatar_id < EARLIEST_FILTERED_ID
    end

    ## URLS

    def url(query = nil, actor = nil)
      storage_policy(actor: actor).download_url(query)
    end

    # Gets the original, uncropped avatar.
    def original_url(actor = nil)
      storage_policy(actor: actor).download_url(orig: 1)
    end

    # Gets the avatar URL with a unique signature
    def unique_url
      url u: unique_signature
    end

    def base_url
      storage_policy.download_url
    end

    def uri_template(internal: false)
      "media:/#{media_uri_path}?s={size}&#{alambic_internal_media_querystring}"
    end

    def unique_signature
      @unique_signature ||= begin
        ids = [owner_id, avatar_id, cropped_x, cropped_y, cropped_width, cropped_height]
        Digest::SHA1.hexdigest("avatar:#{ids.map! { |id| id.to_i }.join(":")}") # rubocop:disable GitHub/InsecureHashAlgorithm
      end
    end

    def avatar_owner_path
      "avatars"
    end

    def avatar_surrogate_key
      "#{avatar_owner_path}/#{avatar_id}"
    end

    def media_uri_path
      File.join(alambic_path_prefix, avatar_oid)
    end

    # GHE:
    # GitHub.storage_legacy_path => "/data/user/alambic_assets/shared"
    # /data/user/alambic_assets/shared/ab/cd/abcdef1234567890
    def alambic_absolute_local_path
      File.join(GitHub.storage_legacy_path, oid[0...2], oid[2...4], oid)
    end

    def alambic_path_prefix
      if GitHub.storage_cluster_enabled?
        avatar_oid[0]
      else
        GitHub.alambic_path_prefix
      end
    end

    def etag
      unique_signature
    end

    def cropped?
      cropped_width > 0 && cropped_height > 0
    end

    def cropped_dimensions
      [cropped_x, cropped_y, cropped_width, cropped_height].join(",") if cropped?
    end

    def audit_log_owner_key(owner = self.owner)
      case owner
      when Organization
        :org
      when User
        :user
      when OauthApplication
        :oauth_application
      when Integration
        :integration
      when Marketplace::Listing
        :marketplace_listing
      when Team
        :team
      when Business
        :business
      when RepositoryAction
        :repository_action
      else
        raise "avatar on #{owner.class} not supported"
      end
    end

    alias surrogate_key avatar_surrogate_key
  end

  include Shared

  # See Avatar::UrlHelper
  def avatar_id
    id
  end

  # Public: Remove the avatar from the CDN and prevent it from being proxied by
  # Alambic by settings its `quarantined` flag to `true`.
  #
  # See the following for additional details on this method's implementation:
  #   * https://github.com/github/object-storage/issues/343
  #   * https://github.com/github/alambic/tree/main/docs/avatars
  #   * https://github.com/github/github/pull/196293
  #
  # reason - String explaining the reason this avatar has been quarantined.
  def quarantine(reason:)
    return false if GitHub.storage_cluster_enabled?
    if update(quarantined: true)
      purge_cdn

      opts = { avatar: self, reason: reason }
      opts[:user] = self.owner if self.owner.is_a? User
      opts[:team] = self.owner if self.owner.is_a? Team
      opts[:business] = self.owner if self.owner.is_a? Business
      opts[:integration] = self.owner if self.owner.is_a? Integration
      opts[:oauth_application] = self.owner if self.owner.is_a? OauthApplication
      opts[:marketplace_listing] = self.owner if self.owner.is_a? Marketplace::Listing
      opts[:repository_action] = self.owner if self.owner.is_a? RepositoryAction

      instrument :quarantine, opts
      true
    else
      false
    end
  end

  # Public: Allow the avatar to be cached in the CDN and proxied by Alambic by
  # settings its `quarantined` flag to `false`. We also have to purge the CDN
  # to ensure that placeholder images (like identicons) that may have been
  # loaded while the avatar was quarantined are removed now that the real
  # avatar is once again available for viewing.
  def unquarantine(reason:)
    return false if GitHub.storage_cluster_enabled?
    if update(quarantined: false)
      purge_cdn

      opts = { avatar: self, reason: reason }
      opts[:user] = self.owner if self.owner.is_a? User
      opts[:team] = self.owner if self.owner.is_a? Team
      opts[:business] = self.owner if self.owner.is_a? Business
      opts[:integration] = self.owner if self.owner.is_a? Integration
      opts[:oauth_application] = self.owner if self.owner.is_a? OauthApplication
      opts[:marketplace_listing] = self.owner if self.owner.is_a? Marketplace::Listing
      opts[:repository_action] = self.owner if self.owner.is_a? RepositoryAction

      instrument :unquarantine, opts
      true
    else
      false
    end
  end

  def purge
    destroy
    return if GitHub.storage_cluster_enabled?
    purge_cdn
  end

  def instrument_destroy
    instrument :destroy, :avatar => self, audit_log_owner_key => owner
  end
end
