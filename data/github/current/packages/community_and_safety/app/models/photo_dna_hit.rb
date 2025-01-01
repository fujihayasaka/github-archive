# typed: true
# frozen_string_literal: true

class PhotoDnaHit < ApplicationRecord::Collab

  # Please note, this retention period is a requirement by law.
  # Do not change this value without input from our Legal team
  RETENTION_PERIOD = 90.days

  belongs_to :content, polymorphic: true
  belongs_to :uploader, class_name: "User"

  include GitHub::Validations

  validates_presence_of :content
  validates :content_type, length: { maximum: 15 }, unicode3: true
  before_save :ghostify_nil_user

  scope :for_user_asset, ->(user_asset) { where(content_id: user_asset, content_type: "UserAsset") }
  scope :purgeable, -> { where(purged: false).where("created_at < ?", RETENTION_PERIOD.ago) }

  def ghostify_nil_user
    self.uploader = User.ghost if uploader.nil?
  end

  def purge_content!
    return mark_as_purged if content.nil?

    # remove when .purge implemented for all content types
    unless content.respond_to?(:purge)
      Failbot.report("Purge attempted on content with class #{content.class} and id #{content.id}, but not implemented yet")
      return mark_as_purged
    end

    if content.purge
      mark_as_purged
    else
      Failbot.report("Purge failed for flagged content with class #{content.class} and id #{content.id}")
    end
  end

  private

  def mark_as_purged
    self.update(purged: true)
  end
end
