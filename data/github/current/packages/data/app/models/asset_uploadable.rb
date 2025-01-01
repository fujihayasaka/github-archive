# typed: false
# frozen_string_literal: true

require "delegate"

# Describes a model that stores files through the Alambic service.  These
# records are treated as immutable.  You change your avatar by uploading a new
# one, not changing the existing one.
#
# Uploadable models are joined to an Asset model.  The Asset model tracks the
# core metadata for the asset.  Only meta data for a unique file that never
# changes: size, signatures, etc.  An Asset may be related to one or more
# Uploadable models through the Asset::Reference model.
#
# Uploadable models should track their uploader and a parent object.  The parent
# object is typically used to figure out access control.  For example, a
# ReleaseAsset belongs to a Release.  Whether someone can upload or view a
# ReleaseAsset depends on the Release permissions.
#
# Uploadable models may also store their own metadata.  Some properties like
# filenames or content types should not be stored in the Asset model, because
# they can vary.
#
# Will eventually replace the legacy Uploadable module.
module AssetUploadable
  def self.included(base)
    super(base)

    base.has_many :asset_references, as: :uploadable, class_name: "Asset::Reference"
    base.has_many :assets, through: :asset_references

    # asset meta data
    base.delegate :update_meta, :set_meta, to: :asset

    base.extend(ClassMethods)
  end

  module Purgeable
    def self.enabled?
      !@disabled
    end

    def self.enable!
      @disabled = false
      nil
    end

    def self.disable!
      @disabled = true
      nil
    end

    def purge_cdn
      AssetUploadable::Cdn.purge(*purged_keys)
    end

    def purged_keys
      [surrogate_key]
    end

    # ActiveRecord callback
    def purge_keys_from_cdn
      enqueue_purge_cdn_job
    end

    # ActiveRecord callback
    def update_keys_in_cdn
      enqueue_purge_cdn_job
    end

    def enqueue_purge_cdn_job
      return unless AssetUploadable::Purgeable.enabled?

      options = { "keys" => purged_keys }
      s = GitHub.alambic_cdn_delay.to_i
      if s < 1
        PurgeAlambicCdnJob.perform_later(options)
      else
        PurgeAlambicCdnJob.set(wait: s.seconds).perform_later(options)
      end
    end
  end

  # class methods for all AssetUploadable models.
  module ClassMethods
    def create_for_policy(uploader, params)
      meta = uploadable_policy_attributes.inject({}) do |hash, key|
        hash.update(key => params[key.to_s])
      end
      UploadablePolicyDelegator.new(validate_asset(uploader, meta))
    end

    # Builds the asset in memory for validation before the data is actually
    # posted to the server.  This is used by the policy pre-flight request to
    # verify the model attributes and get the correct URL for uploading the
    # asset contents.
    def validate_asset(uploader, meta)
      asset = Asset.new
      asset.set_meta(meta)
      asset.width = asset.height = 3000

      uploadable = build_for_asset_validation(uploader, meta)
      uploadable.asset = asset
      uploadable
    end
  end

  # callback when the uploadable object has been uploaded.  This isn't
  # necessarily when this db row has been created though.
  def after_upload(meta)
    update_meta(meta)
  end

  def alambic_headers
  end

  def alambic_filters
  end

  def alambic_initial_filters
  end

  def archive?(asset)
    asset.references.count.zero?
  end

  def dereference_asset
    asset.dereference!(self) if asset
  end

  # Validates this model has 1 asset in Production
  def storage_ensure_asset
    if !new_record?
      case assets.size
      when 0
        errors.add(:asset_id, "is required") unless asset && asset_id_changed?
        return
      when 1
        if assets.first.id != asset_id
          errors.add(:asset_id, "incorrect asset")
          return
        end
      else
        errors.add(:asset_id, "can only have one asset")
        return
      end
    end

    asset || begin
      errors.add(:asset_id, "is required")
      nil
    end
  end

  class UploadablePolicyDelegator < SimpleDelegator
    def new_record?
      !__getobj__.valid?
    end
  end
end
