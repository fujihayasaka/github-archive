# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::GitHubPullRequestMetadata < CopilotSpaceResource::Metadata
  attr_reader :repository_id, :repository, :number, :pull_request, :issue

  sig { override.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json)
    new(
      repository_id: json["repository_id"],
      number: json["number"],
    )
  end

  def initialize(repository_id:, number:)
    @repository_id = repository_id
    @number = number
    if @number.present? && repository_id.present?
      @repository = Repositories::Public.find_active(@repository_id)

      @issue = Issue.includes(:pull_request).find_by(repository_id: @repository_id, number: @number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      @pull_request = @issue.pull_request if @issue
      @title = @pull_request.title if @pull_request
    end
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubPullRequestMetadata))
  end
  def to_copilot_config_twirp(opts: {})
    return unless pull_request
    # Eager load associations
    ActiveRecord::Associations::Preloader.new(records: [pull_request], associations: { review_threads: { review_comments: :user } }).call

    diffs = pull_request.diffs.map do |diff_entry|
      {
        sha: diff_entry.b_sha,
        file_name: diff_entry.path,
        status: diff_entry.status_label,
        additions: diff_entry.additions,
        deletions: diff_entry.deletions,
        changes: diff_entry.changes,
        patch: diff_entry.text.try(:length).to_i > 0 && !diff_entry.binary_text? ? diff_entry.unicode_text : nil,
        previous_filename: diff_entry.renamed? ? diff_entry.a_path : nil,
        url: "#{GitHub.url}/#{repository.name_with_display_owner}/pull/#{pull_request.number}/files#diff-#{diff_entry.path_digest}"
      }
    end

    comments = []
    review_comments = []
    # Code level thread comments
    review_comments = pull_request.review_threads.flat_map do |thread|
      thread.comments.map do |comment|
        {
          comment: {
            author: comment.user.display_login,
            contents: comment.body,
            url: comment.url,
            created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
          },
          file_path: thread.path,
        }
      end
    end

    # Comments on the pull request itself
    issue_comments = pull_request.issue.comments.includes(:user).filter_map do |comment|
      # Skip bundle stats comments from Bot
      if !CopilotSpaceResource.exclude_comment?(comment)
        {
          author: comment.user.display_login,
          contents: comment.body,
          url: comment.url,
          created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
        }
      end
    end

    # Comments made when submitting a PR review
    reviews_with_body = pull_request.reviews.includes(:user).where.not(body: nil).map do |review|
      {
        author: review.user.display_login,
        contents: review.body,
        url: review.url,
        created_at: Google::Protobuf::Timestamp.new(seconds: review.created_at.to_i),
      }
    end

    comments = (issue_comments + reviews_with_body).sort_by { |comment| comment[:created_at].seconds }

    labels = issue.labels.map do |label|
      {
        name: label.name,
        description: label.description,
      }
    end

    MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubPullRequestMetadata.new(
      owner: repository.owner_display_login,
      name: repository.name,
      number: number,
      title: pull_request.title,
      contents: pull_request.body,
      repo_id: repository.id,
      author: pull_request.user&.display_login,
      base_ref: pull_request.base_ref,
      head_ref: pull_request.head_ref,
      state: pull_request.state,
      additions: pull_request.additions,
      deletions: pull_request.deletions,
      diff_entries: diffs,
      url: pull_request.url,
      id: pull_request.id,
      comments: comments,
      review_comments: review_comments,
      labels: labels,
    )
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def to_url_validation_payload
    {
      type: CopilotSpaceResource::Constants::GITHUB_PULL_REQUEST,
      number: number,
      url: pull_request.url,
      nwo: repository.name_with_display_owner,
      title: pull_request.title,
      repositoryId: repository.id,
    }
  end
end
