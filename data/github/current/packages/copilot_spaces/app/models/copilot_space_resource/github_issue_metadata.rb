# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::GitHubIssueMetadata < CopilotSpaceResource::Metadata
  attr_reader :repository_id, :repository, :number, :issue

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
    if @number.present? && @repository_id.present?
      @repository = Repositories::Public.find_active(@repository_id)
      @issue = Issue.find_by(repository_id: @repository_id, number: @number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubIssueMetadata))
  end
  def to_copilot_config_twirp(opts: {})
    return unless issue
    # Eager load associations
    ActiveRecord::Associations::Preloader.new(records: [issue], associations: { comments: :user }).call

    comments = []
    labels = []
    comments = issue.comments.map do |comment|
      {
        author: comment.user.display_login,
        contents: comment.body,
        url: comment.url,
        created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
      }
    end

    labels = issue.labels.map do |label|
      {
        name: label.name,
        description: label.description,
      }
    end

    MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubIssueMetadata.new(
      owner: repository.owner_display_login,
      name: repository.name,
      number: number,
      contents: issue.body,
      title: issue.title,
      repo_id: repository.id,
      author: issue.user.display_login,
      url: issue.url,
      id: issue.id,
      comments: comments,
      labels: labels,
    )
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def to_url_validation_payload
    {
      type: CopilotSpaceResource::Constants::GITHUB_ISSUE,
      number: number,
      url: issue.url,
      nwo: repository.name_with_display_owner,
      title: issue.title,
      repositoryId: repository.id,
    }
  end
end
