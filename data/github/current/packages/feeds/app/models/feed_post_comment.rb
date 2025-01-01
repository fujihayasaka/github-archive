# typed: false
# frozen_string_literal: true

class FeedPostComment < ApplicationRecord::Ballast
  extend GitHub::Encoding

  include GitHub::Relay::GlobalIdentification
  include GitHub::UserContent
  include GitHub::RateLimitedCreation

  include FeedPostComment::ReactionsDependency

  force_utf8_encoding :body

  belongs_to :user, required: true, inverse_of: :feed_post_comments
  belongs_to :feed_post, required: true, inverse_of: :comments
  belongs_to :parent_comment, class_name: "FeedPostComment"

  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT },
    unicode: true, allow_blank: false
  validates :body, presence: true
  validate :user_has_verified_email
  validate :user_is_not_spammy
  validate :ensure_parent_comment_is_for_post

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  def deleted?
    !deleted_at.nil?
  end

  def deletable_by?(actor)
    actor.id == user_id
  end

  private

  def user_has_verified_email
    return unless user && feed_post

    if user.should_verify_email?
      errors.add(:user, "must have a verified email address")
    end
  end

  def ensure_parent_comment_is_for_post
    return unless parent_comment && feed_post_id

    if parent_comment.feed_post_id != feed_post_id
      errors.add(:parent_comment, "is associated with a different post")
    end
  end

  def parent_comment_is_not_deleted
    return unless parent_comment

    if parent_comment.deleted?
      errors.add(:parent_comment, "has been deleted and cannot be replied to")
    end
  end

  def user_is_not_spammy
    return unless GitHub.spamminess_check_enabled? && user

    if user.spammy?
      errors.add(:base, "#{user.login} cannot create a comment at this time.")
    end
  end

  def instrument_create
    GlobalInstrumenter.instrument("feed_post_comment.create", {
      feed_post_comment: self,
      feed_post_id: feed_post_id,
      method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_CREATE,
    })
  end

  def instrument_update
    GlobalInstrumenter.instrument("feed_post_comment.update", {
      feed_post_comment: self,
      feed_post_id: feed_post_id,
      method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_UPDATE,
    })
  end

  def instrument_destroy
    GlobalInstrumenter.instrument("feed_post_comment.delete", {
      feed_post_comment: self,
      feed_post_id: feed_post_id,
      method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_DELETE,
    })
  end
end
