# typed: true
# frozen_string_literal: true

class ReactionGroup
  include Reactable
  include PreloadableAttributes

  # Do not instantiate directly.
  #
  # Use Platform::Loaders::ReactionGroup to fetch this data instead.
  #
  def initialize(subject:, emotion:, total_count:, created_at:)
    @subject = subject
    @emotion = emotion

    @total_count = total_count
    @created_at = created_at
  end

  attr_reader :subject, :emotion, :total_count, :created_at, :user_ids, :has_reacted

  attr_preloadable :user_ids, :has_reacted # todo: has_reacted should be per viewer

  def content
    emotion.content
  end

  # Public: Return all user logins in all reaction groups from all the comments.
  #
  # reaction_groups_by_comment_id - a hash of DiscussionComment.ID => Array of ReactionGroup
  #
  # Returns a Hash of DiscussionComment.ID => (Hash of ReactionGroup.Content => Array of String)
  def self.user_logins_by_comment_id_by_reaction_group_content(reaction_groups_by_comment_id)
    all_user_ids = reaction_groups_by_comment_id
      .values
      .map { |groups| groups.map(&:user_ids) }
      .flatten
      .uniq
    user_logins = User.where(id: all_user_ids).select(&:display_login)
    users_by_id = user_logins.index_by(&:id).transform_values(&:display_login)

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
