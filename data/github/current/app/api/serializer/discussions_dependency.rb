# typed: true
# frozen_string_literal: true

module Api::Serializer::DiscussionsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::UserDependency }
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::ReactionsDependency }

  # Creates a Hash to be serialized to JSON.
  #
  # discussion   - Discussion instance.
  # options - Hash
  #           :repo         - Either a Repository or a String of the Repository
  #                           path: "user/repo"
  #
  # Returns a Hash if the Discussion exists, or nil.
  sig do
    params(
      discussion: Discussion,
      options: T.any(T::Hash[Symbol, T.untyped], GitHub::Options),
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def discussion_hash(discussion, options = {})
    return nil if discussion.nil?

    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, discussion)
    discussion_path = "/repos/#{repo}/discussions/#{discussion.number}"

    # We cannot currently change the value of `state` of our webhooks, since it is a breaking change.
    # So we have to keep the state as `locked` for now. We can change this in the future if
    # we end up having a process for versioning webhooks.
    # https://thehub.github.com/epd/engineering/products-and-services/public-apis/rest/lifecycle/change/#non-breaking-changes
    state = discussion.locked? ? "locked" : discussion.state

    hash = {
      repository_url: url("/repos/#{repo}", options),
      category: discussion_category_hash(T.must(discussion.category), content_options(options)),
      answer_html_url: discussion.chosen_comment&.url,
      answer_chosen_at: discussion.async_chosen_comment_selected_at.sync,
      answer_chosen_by: user_hash(discussion.chosen_comment_selected_by_user, content_options(options)),
      html_url: discussion.url,
      id: discussion.id,
      node_id: global_id_for(discussion, options),
      number: discussion.number,
      title: discussion.title,
      user: user_hash(discussion.safe_user, content_options(options)),
      labels: discussion.labels.map { |l| label_hash(l, options.merge(repo: repo)) },
      state: state,
      state_reason: discussion.state_reason,
      locked: discussion.locked?,
      comments: discussion.comments.count,
      created_at: time(discussion.created_at),
      updated_at: time(discussion.updated_at),
      author_association: discussion.author_association(options[:current_user]).to_s,
    }

    active_lock_reason = discussion.active_lock_reason&.downcase&.dasherize
    hash[:active_lock_reason] = active_lock_reason

    if options[:repositories] || options.accepts_semantic_version?("extended-search-results")
      hash[:repository] = repository_hash(T.must(discussion.repository), options)
    end

    hash.update mime_body_hash(discussion, options)
    hash[:reactions] = reactions_rollup(discussion, url("#{discussion_path}/reactions", options))
    hash[:timeline_url] = url("#{discussion_path}/timeline", options)

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # category - category instance.
  # options  - Hash of options
  #
  # Returns a Hash if the Category exists, or nil.
  sig do
    params(
      category: DiscussionCategory,
      options: T.any(T::Hash[Symbol, T.untyped], GitHub::Options),
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def discussion_category_hash(category, options = {})
    return nil if category.nil?

    options = Api::SerializerOptions.from(options)

    {
      id: category.id,
      node_id: global_id_for(category, options),
      repository_id: category.repository_id,
      emoji: category.emoji,
      name: category.name,
      description: category.description,
      created_at: category.created_at,
      updated_at: category.updated_at,
      slug: category.slug,
      is_answerable: category.supports_mark_as_answer
    }
  end

  sig do
    params(
      comment: DiscussionComment,
      options: T.any(T::Hash[Symbol, T.untyped], GitHub::Options),
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def discussion_comment_hash(comment, options = {})
    return nil if !comment
    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, comment)

    hash = {
      id: comment.id,
      node_id: global_id_for(comment, options),
      html_url: comment.permalink,
      parent_id: comment.parent_comment_id,
      child_comment_count: comment.comment_count,
      repository_url: repo,
      discussion_id: comment.discussion_id,
      author_association: comment.author_association(options[:current_user]).to_s,
      user: user_hash(comment.safe_user, content_options(options)),
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at)
    }.update(mime_body_hash(comment, options))

    hash[:reactions] = reactions_rollup(comment, url("/repos/#{repo}/discussions/comments/#{comment.id}/reactions", options))
    hash
  end
end
