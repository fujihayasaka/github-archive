# typed: true
# frozen_string_literal: true
class DiscussionTimeline::BatchedDiscussionComment
  # Public: This method is used to load only the discussion comments that will be rendered on a discussion page.
  #
  # discussion - a Discussion
  # viewer - the currently authenticated User or nil
  # initial_count - Number of replies to load for each top-level discussion comment
  # items_per_page - The number of top level comments to load per page
  #
  # Returns a list of pairs of [DiscussionComment, DiscussionTimeline::Placeholder::DiscussionComment].
  sig do
    params(
      discussion: T.untyped,
      viewer: T.untyped,
      initial_count: T.untyped,
      items_per_page: T.untyped,
      last_read_at: T.untyped
    ).returns(T.untyped)
  end
  def self.load(discussion, viewer, initial_count:, items_per_page: nil, last_read_at: nil)
    results = DiscussionComment.for_discussion(discussion.id)
      .filter_spam_for(viewer)
      .order(id: :asc)
      .pluck(:id, :parent_comment_id, :created_at)

    placeholders = results.map do |id, parent_comment_id, created_at|
      DiscussionTimeline::Placeholder::DiscussionComment.new(
        id: id,
        parent_comment_id: parent_comment_id,
        created_at: created_at,
        reply_max_count: initial_count,
        last_read_at: last_read_at
      )
    end

    all_top_level_placeholders = placeholders.select(&:top_level_comment?)

    top_level_placeholders = all_top_level_placeholders

    top_level_placeholders_by_id = top_level_placeholders.each_with_object({}) do |placeholder, hash|
      hash[placeholder.id] = placeholder
    end

    placeholders.each do |placeholder|
      parent_placeholder = top_level_placeholders_by_id[placeholder.parent_comment_id]
      parent_placeholder&.add_reply(placeholder) if placeholder.reply?
    end

    placeholder_batch = all_top_level_placeholders
      .flat_map { |placeholder| [placeholder] + placeholder.reply_placeholders }
      .sort_by(&:id)
    placeholder_comment_ids = placeholder_batch.map(&:id)
    comments = DiscussionComment.where(id: placeholder_comment_ids).order(id: :asc)
    comments.zip(placeholder_batch)
  end
end
