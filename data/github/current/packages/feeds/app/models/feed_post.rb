# typed: false
# frozen_string_literal: true

class FeedPost < ApplicationRecord::Ballast
  extend GitHub::Encoding

  include GitHub::Relay::GlobalIdentification
  include GitHub::UserContent
  include GitHub::RateLimitedCreation

  include FeedPost::RateLimitDependency
  include FeedPost::ReactionsDependency

  class MethodNotSupported < StandardError; end

  force_utf8_encoding :body

  belongs_to :author, class_name: "User", required: true,
    inverse_of: :authored_feed_posts
  belongs_to :owner, class_name: "User", required: true,
    inverse_of: :owned_feed_posts
  belongs_to :topic

  has_many :feed_post_references
  destroy_dependents_in_background :feed_post_references
  has_many :user_mentions, through: :feed_post_references,
    source: :reference, source_type: "User", disable_joins: true
  has_many :comments, class_name: "FeedPostComment", inverse_of: :feed_post
  destroy_dependents_in_background :comments

  scope :owned_by, ->(user) { where(owner_id: user.id) }
  scope :authored_by, ->(user) { where(author_id: user.id) }

  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true,
    allow_blank: false
  validate :author_has_verified_email
  validate :author_is_not_spammy
  validate :owner_is_not_spammy
  validate :author_can_post_as_owner

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  def self.create_with_references(params)
    FeedPost.transaction do
      post = FeedPost.create!(params)
      FeedPostReference.from_post(post).each(&:save!)
      # create event in conduit
      conduit_client = Conduit::Client.new
      conduit_client.create_feed_post_event(feed_post: post)
      post
    end
  rescue ActiveRecord::RecordInvalid, Conduit::Client::Error => e
    Failbot.report(e)
    nil
  end

  # Wrap the destroy method to additionally delete the event in conduit
  # These have to be run as a transaction to ensure data integrity between conduit and dotcom;
  # therefore before_destroy hooks could not be used
  def destroy
    FeedPost.transaction do
      raise ActiveRecord::Rollback.new unless super
      conduit_client = Conduit::Client.new
      conduit_client.delete_feed_post_event(feed_post_id: self.id)
    end
    self
  rescue Conduit::Client::Error => e
    Failbot.report(e)
    nil
  end

  def destroy!
    raise MethodNotSupported.new("FeedPost#destroy! is not supported. Use FeedPost#destroy instead")
  end

  def delete
    raise MethodNotSupported.new("FeedPost#delete is not supported. Use FeedPost#destroy instead")
  end

  # TODO: This should ultimately run through authzd
  # similar to Discussion#deletable_by?
  #
  # see https://github.com/github/authzd/blob/master/config/policies/discussions.json#L137
  def deletable_by?(actor)
    actor.id == author_id || actor.id == owner_id
  end

  def to_twirp
    MonolithTwirp::Conduit::Feeds::V1::FeedPost.new(
      id: self.id,
      owner: MonolithTwirp::Conduit::Feeds::V1::User.new(
        id: owner_id,
        login: owner.login,
        type: "TYPE_USER",
      ),
      author: MonolithTwirp::Conduit::Feeds::V1::User.new(
        id: author_id,
        login: author.login,
        type: "TYPE_USER",
      ),
      references: references_to_twirp,
      topic_id: topic_id,
    )
  end

  def to_twirp_feed_item
    MonolithTwirp::Conduit::Feeds::V1::FeedItem.new(
      actor: MonolithTwirp::Conduit::Feeds::V1::User.new(
        id: owner_id,
        login: owner.login,
        type: "TYPE_USER",
      ),
      action: "ACTION_CREATED",
      time: Time.at(created_at),
      subject_type: "SUBJECT_TYPE_FEED_POST",
      relationship: "self",
      gatherer: "monolith_feed_post",
      card_retrieved_id: "",
      related_items: [],
      related_by: "RELATED_BY_NONE",
      event_id: id,
      event_type: "feed_post",
      feed_post_subject: self.to_twirp,
    )
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    async_owner.then(&:async_target_for_conditional_access)
  end

  private

  def references_to_twirp
    feed_post_references.map do |reference|
      MonolithTwirp::Conduit::Feeds::V1::FeedPostReference.new(
        referenced_object_id: reference.reference_id,
        referenced_object_type: :REFERENCE_OBJECT_TYPE_USER,
        action_type: :REFERENCE_ACTION_MENTION
      )
    end
  end

  def author_has_verified_email
    return unless author

    if author.should_verify_email?
      errors.add(:author, "must have a verified email address")
    end
  end

  def author_is_not_spammy
    return unless GitHub.spamminess_check_enabled? && author

    if author.spammy?
      errors.add(:base, "#{author.login} cannot create a post at this time.")
    end
  end

  def owner_is_not_spammy
    return unless GitHub.spamminess_check_enabled? && owner

    if owner.spammy?
      errors.add(:base, "#{owner.login} cannot create a post at this time.")
    end
  end

  def author_can_post_as_owner
    return unless author && owner
    return if author == owner

    if owner.user?
      errors.add(:author, "can't create a post as #{owner.login}")
    end

    if !author.owned_organization_ids.include?(owner_id)
      errors.add(:author, "can't create a post as #{owner.login}")
    end
  end

  def instrument_create
    GlobalInstrumenter.instrument("feed_post.create", {
      feed_post: self,
      method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_CREATE,
    })
  end

  def instrument_update
    GlobalInstrumenter.instrument("feed_post.update", {
      feed_post: self,
      method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_UPDATE,
    })
  end

  def instrument_destroy
    GlobalInstrumenter.instrument("feed_post.delete", {
      feed_post: self,
      method: Conduit::AnalyticsHelper::InteractionMethod::INTERACTION_METHOD_DELETE,
    })
  end
end
