# typed: true
# frozen_string_literal: true

class DiscussionIndexFeed
  extend T::Sig

  include GitHub::Memoizer

  sig do
    params(
      repository: T.untyped,
      discussions: T.untyped,
      all_discussions: T.untyped,
      viewer: T.untyped,
      cap_filter: T.untyped
    ).void
  end
  def initialize(repository:, discussions:, all_discussions:, viewer:, cap_filter:)
    @repository = repository
    @discussions = discussions
    @all_discussions = all_discussions
    @viewer = viewer
    @cap_filter = cap_filter
  end

  attr_reader :repository, :discussions, :all_discussions, :viewer, :cap_filter

  sig { returns(T.untyped) }
  def preload_for_display
    GitHub::PrefillAssociations.prefill_associations(all_discussions, [:user])
    GitHub::PrefillAssociations.prefill_associations(discussions, discussion_associations_to_preload)
  end

  sig { returns(T.untyped) }
  def discussion_associations_to_preload
    [:labels]
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def action_or_role_level_for(discussion_or_comment)
    author_role_preloader.action_or_role_level_for(discussion_or_comment)
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def body_html_for(discussion_or_comment)
    preloaded_body_html[discussion_or_comment]
  end

  sig { params(discussion: T.untyped).returns(T.untyped) }
  def fast_reactions_for(discussion)
    fast_reactions_for_discussion_by_id[discussion.id] || {}
  end

  sig { returns(T.untyped) }
  def repo_name
    repository.name
  end

  sig { returns(T.untyped) }
  def repo_owner_login
    repository.owner_display_login
  end

  private

  memoize def chosen_comments
    ids = discussions.map(&:chosen_comment_id).compact
    DiscussionComment.where(id: ids)
  end

  memoize def author_role_preloader
    DiscussionTimeline::AuthorRolePreloader.new(
      rendered_records: discussions + chosen_comments,
      repository: repository
    )
  end

  def preload_author_roles
    author_role_preloader.preload
  end

  # Returns a Hash{DiscussionComment|Discussion => String}.
  memoize def preloaded_body_html
    async_all_comments_and_discussion_bodies.sync
  end

  def async_all_comments_and_discussion_bodies
    renderer = DiscussionTimeline::BodyRenderer.new(discussions + chosen_comments, context: {
      viewer: viewer,
      cap_filter: cap_filter,
      unfurl_references: true
    })
    renderer.async_body_html_by_record
  end

  memoize def fast_reactions_for_discussion_by_id
    discussion_ids_contents_counts = DiscussionReaction.where(discussion_id: discussions.map(&:id))
      .group(:discussion_id, :content)
      .pluck(:discussion_id, :content, Arel.sql("count(*)"))
    discussion_ids_contents_counts.each_with_object({}) do |(discussion_id, content, count), hash|
      hash[discussion_id] ||= Hash.new({})
      hash[discussion_id][content] = count
    end
  end
end
