# typed: true
# frozen_string_literal: true

module Api::Serializer::PullRequestReviewsDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  CommentMimeBodyFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Comment {
      body
      bodyHTML

      # TODO: Consider adding bodyText to Comment interface
      ... on PullRequestReview {
        bodyText
      }
      ... on PullRequestReviewComment {
        bodyText
      }
    }
  GRAPHQL

  def graphql_comment_mime_body_hash(comment, options)
    comment = CommentMimeBodyFragment.new(comment)
    params   = options[:mime_params] || []
    full     = params.include? :full
    any_body = false
    hash     = {}
    if full || params.include?(:html)
      any_body = true
      hash.update body_html: comment.body_html
    end
    if full || params.include?(:text)
      any_body = true
      hash.update body_text: comment.body_text
    end
    if full || !any_body || params.include?(:raw)
      hash.update body: comment.body
    end

    hash
  end

  def pull_request_review_hash(review, options = {})
    return nil unless review
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, review)
    pull = options[:pull_request] || review.pull_request
    pull_url = url("/repos/#{repo}/pulls/#{pull.number}", options)

    {
      id: review.id,
      node_id: global_id_for(review, options),
      user: user_hash(review.user, content_options(options)),
      body: review.body,
      commit_id: review.head_sha,
      submitted_at: time(review.submitted_at),
      state: PullRequestReview.state_name(review.state),
      html_url: review.permalink.to_s,
      pull_request_url: pull_url,
      _links: {
        html: { href: review.permalink.to_s },
        pull_request: { href: pull_url.to_s },
      },
    }.tap do |review_hash|
      review_hash[:updated_at] = time(review.updated_at) if review.updated_at

      unless options[:skip_author_association]
        review_hash[:author_association] = review.author_association(options[:current_user]).to_s
      end
    end.update(mime_body_hash(review, options))
  end

  def requested_reviewers_hash(pull, options = {})
    teams, users = pull.pending_review_requests.map(&:reviewer).partition { |r| r.is_a?(Team) }
    {
      users: users.map { |u| simple_user_hash(u, content_options(options)) },
      teams: teams.map { |t| team_hash(t, options) },
    }
  end

  PullRequestReviewFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on PullRequestReview {
      id
      databaseId
      body
      bodyHTML
      bodyText
      state
      submittedAt
      url
      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      commit {
        oid
      }
      pullRequest {
        number
        repository {
          resourcePath
        }
      }
      ...Api::Serializer::PullRequestReviewsDependency::CommentMimeBodyFragment
      authorAssociation
    }
  GRAPHQL

  def graphql_pull_request_review_hash(review, options = {})
    return nil unless review
    review = Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment.new(review)

    options = Api::SerializerOptions.from(options)
    pull = review.pull_request
    repo = pull.repository.resource_path
    pull_url = url("/repos#{repo}/pulls/#{pull.number}", options)

    hash = {
      id: review.database_id,
      node_id: review.id,
      user: graphql_simple_user_hash(review.author, options),
      body: review.body,
      state: review.state,
      html_url: review.url.to_s,
      pull_request_url: pull_url,
      author_association: review.author_association,
      _links: {
        html: { href: review.url.to_s },
        pull_request: { href: pull_url.to_s },
      },
    }.update(graphql_comment_mime_body_hash(review, options))

    hash[:submitted_at] = time(review.submitted_at) if review.submitted_at
    hash[:commit_id] = review.commit&.oid

    hash
  end

  def pull_request_review_comment_hash(comment, options = {})
    return nil unless comment&.pull_request

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, comment)
    pull_request = options[:pull_request] || comment.pull_request
    pull_url = url("/repos/#{repo}/pulls/#{pull_request.number}", options)
    review_url = url("/repos/#{repo}/pulls/comments/#{comment.id}", options)
    thread = T.let(comment.pull_request_review_thread, T.nilable(PullRequestReviewThread))

    hash = {
      url: review_url,
      pull_request_review_id: comment.pull_request_review_id,
      id: comment.id,
      node_id: global_id_for(comment, options),
      diff_hunk: comment.diff_hunk || "",
      path: comment.path,
      commit_id: comment.commit_id,
      original_commit_id: comment.original_commit_id,
      user: user_hash(comment.user, content_options(options)),
      body: comment.body,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      html_url: comment.url.to_s,
      pull_request_url: pull_url,
      author_association: comment.author_association_symbol(options[:current_user]).to_s.upcase,
      _links: {
        self: { href: review_url.to_s },
        html: { href: comment.url.to_s },
        pull_request: { href: pull_url.to_s },
      },
    }.update(mime_body_hash(comment, options))

    hash[:reactions] = reactions_rollup(comment, review_url + "/reactions")
    hash[:start_line] = comment.start_line_number
    hash[:original_start_line] = comment.original_start_line
    hash[:start_side] = comment.start_side&.upcase
    hash[:line] = comment.on_line? ? comment.safe_line : 1
    hash[:original_line] = comment.on_line? ? comment.original_line : 1
    hash[:side] = comment.side&.upcase
    hash[:in_reply_to_id] = comment.reply_to_id if comment.reply?

    unless options.changeset_active?(:remove_diff_relative_comment_fields)
      hash[:original_position] = comment.original_position.is_a?(Integer) ? comment.original_position : 1
      hash[:position] = comment.position.is_a?(Integer) ? comment.position : 1
    end

    hash[:subject_type] = thread&.subject_type

    if positioning = thread&.preloaded_positioning
      hash[:positioning] = PullRequests::CommentPosition::Positions::Rest.serialize(positioning)
    end

    hash
  end

  def pull_request_review_comment_without_positioning_hash(comment, options = {})
    return nil unless comment&.pull_request

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, comment)
    pull_url = url("/repos/#{repo}/pulls/#{comment.pull_request.number}", options)
    review_url = url("/repos/#{repo}/pulls/comments/#{comment.id}", options)

    hash = {
      id: comment.id,
      node_id: global_id_for(comment, options),
      url: review_url,
      pull_request_review_id: comment.pull_request_review_id,
      diff_hunk: comment.diff_hunk || "",
      path: comment.path,
      position: comment.position.is_a?(Integer) ? comment.position : 1,
      original_position: comment.original_position.is_a?(Integer) ? comment.original_position : 1,
      commit_id: comment.commit_id,
      user: user_hash(comment.user, content_options(options)),
      body: comment.body,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      html_url: comment.url.to_s,
      pull_request_url: pull_url,
      author_association: comment.author_association_symbol(options[:current_user]).to_s.upcase,
      _links: {
        self: { href: review_url.to_s },
        html: { href: comment.url.to_s },
        pull_request: { href: pull_url.to_s },
      },
      original_commit_id: comment.original_commit_id,
    }.update(mime_body_hash(comment, options))

    hash[:reactions] = reactions_rollup(comment, review_url + "/reactions")
    hash[:in_reply_to_id] = comment.reply_to_id if comment.reply?

    hash
  end

  def minimized_pull_request_review_comment_hash(comment, options = {})
    return nil unless comment&.pull_request

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, comment)
    pull_request = options[:pull_request] || comment.pull_request
    pull_url = url("/repos/#{repo}/pulls/#{pull_request.number}", options)
    review_url = url("/repos/#{repo}/pulls/comments/#{comment.id}", options)

    hash = {
      id: comment.id,
      node_id: global_id_for(comment, options),
      url: review_url,
      pull_request_review_id: comment.pull_request_review_id,
      diff_hunk: comment.diff_hunk || "",
      path: comment.path,
      position: comment.position.is_a?(Integer) ? comment.position : 1,
      original_position: comment.original_position.is_a?(Integer) ? comment.original_position : 1,
      commit_id: comment.commit_id,
      user: user_hash(comment.user, content_options(options)),
      body: comment.body,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      html_url: comment.url.to_s,
      pull_request_url: pull_url,
      _links: {
        self: { href: review_url.to_s },
        html: { href: comment.url.to_s },
        pull_request: { href: pull_url.to_s },
      },
      original_commit_id: comment.original_commit_id,
    }.update(mime_body_hash(comment, options))

    hash[:reactions] = reactions_rollup(comment, review_url + "/reactions")
    hash[:in_reply_to_id] = comment.reply_to_id if comment.reply?

    hash
  end
end
