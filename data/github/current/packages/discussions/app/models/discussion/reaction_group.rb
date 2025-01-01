# typed: true
# frozen_string_literal: true

class Discussion::ReactionGroup
  # Do not instantiate directly.
  #
  # Use Platform::Loaders::{Discussion, DiscussionComment}ReactionGroup to fetch this data instead.
  #
  sig { params(subject: T.untyped, emotion: T.untyped, reactions: T.untyped).void }
  def initialize(subject:, emotion:, reactions:)
    @subject = subject
    @emotion = emotion
    @reactions = reactions.freeze
  end

  attr_reader :subject, :emotion, :reactions

  sig { returns(T.untyped) }
  def content
    emotion.content
  end

  sig { params(user: T.untyped).returns(T.untyped) }
  def user_reacted?(user)
    return false unless user

    user.id.in?(user_ids)
  end

  sig { returns(T.untyped) }
  def created_at
    reactions.first.try(:created_at)
  end

  sig { returns(T.untyped) }
  def total_count
    reactions.count
  end

  sig { returns(T.untyped) }
  def user_ids
    @user_ids ||= reactions.map(&:user_id)
  end

  # Public: Return all user logins in all reaction groups from all the comments.
  #
  # reaction_groups_by_comment_id - a hash of DiscussionComment.ID => Array of ReactionGroup
  #
  # Returns a Hash of DiscussionComment.ID => (Hash of ReactionGroup.Content => Array of String)
  sig { params(reaction_groups_by_comment_id: T.untyped).returns(T.untyped) }
  def self.user_logins_by_comment_id_by_reaction_group_content(reaction_groups_by_comment_id)
    all_user_ids = reaction_groups_by_comment_id
      .values
      .map { |groups| groups.map(&:user_ids) }
      .flatten
      .uniq
    users_by_id = User.where(id: all_user_ids).pluck(:id, :login).to_h

    reaction_groups_array = reaction_groups_by_comment_id.map do |comment_id, reaction_groups|
      result = {}

      reaction_groups.each do |reaction_group|
        result[reaction_group.content] = reaction_group.user_ids.map do |user_id|
          users_by_id[user_id]
        end
      end

      [comment_id, result]
    end

    reaction_groups_array.to_h
  end
end
