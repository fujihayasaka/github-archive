# typed: true
# frozen_string_literal: true

class ImportablePullRequest < PullRequest
  include Importable

  has_one :issue, class_name: "ImportableIssue", foreign_key: :pull_request_id, autosave: true # rubocop:todo Rails/InverseOf
  # rubocop:todo Rails/InverseOf
  has_many :review_requests,
    class_name: "ImportableReviewRequest",
    foreign_key: :pull_request_id,
    autosave: true,
    extend: ReviewRequest::AssociationExtension
  has_many :reviews, class_name: "ImportablePullRequestReview", foreign_key: :pull_request_id
  # rubocop:enable Rails/InverseOf

  # Creates an imported pull request.
  #
  # attributes - Params to create a historical pull request.
  #
  # Returns an ImportablePullRequest.
  def self.build_pull_request(**attributes)
    repository = attributes[:repository]
    owner = repository.owner

    pr_attributes = attributes.slice(:repository, :user, :draft, :base_ref, :head_ref,
                                      :base_sha, :head_sha, :created_at, :merged_at, :status)
                              .merge({ base_user: owner,
                                      base_repository: repository,
                                      head_user: owner,
                                      head_repository: repository })
    self.new(pr_attributes).tap do |pull_request|
      issue_attributes = attributes[:issue_attributes]
      issue = pull_request.build_issue(
        repository: repository,
        user: attributes[:user],
        title: issue_attributes[:title],
        body: issue_attributes[:body],
        number: issue_attributes[:number],
        created_at: attributes[:created_at],
        closed_at: attributes[:closed_at],
        state: attributes[:closed_at].nil? ? "open" : "closed",
        milestone: issue_attributes[:milestone]
      )

      # Backdate updated_at to created_at if repo owner is feature-flagged in
      if owner.feature_enabled?(:octoshift_backdate_updated_at)
        issue.updated_at = pull_request.updated_at = pull_request.created_at
      end
    end
  end

  def type
    "PullRequest"
  end
end
