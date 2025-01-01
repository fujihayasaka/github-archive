# typed: true
# frozen_string_literal: true

module Api::Serializer::PullRequest::CommentsDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  def pull_request_thread_comment_hash(comment, options = {})
    return nil unless comment&.pull_request

    options = Api::SerializerOptions.from(options)

    # in the future, there may be more classes to handle here.
    # `comment.thread` is a deprecated method so we can't use that as a
    # smoothed-out interface.
    thread = comment.pull_request_review_thread

    repo = repo_path(options, comment)
    pull_path = "/repos/#{repo}/pulls/#{comment.pull_request.number}"
    pull_url = url(pull_path)
    thread_link = "#{pull_path}/threads/#{thread.id}"
    comment_link = "#{thread_link}/comments/#{comment.id}"
    reactions_link = "#{comment_link}/reactions"

    hash = {
      url: url(comment_link, options),
      id: comment.id,
      node_id: global_id_for(comment, options),
      user: user_hash(comment.user, content_options(options)),
      body: comment.body,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      html_url: comment.url.to_s,
      pull_request_id: comment.pull_request.number,
      author_association: comment.author_association(options[:current_user]).to_s,
      _links: {
        self: { href: url(comment_link, options) },
        html: { href: comment.url.to_s },
        pull_request: { href: pull_url.to_s },
        thread: { href: url(thread_link, options) },
        reactions: { href: url(reactions_link, options) }
      },
    }

    hash
  end
end
