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
    pr_attributes = attributes.slice(:repository, :user, :draft, :base_ref, :head_ref,
                                      :base_sha, :head_sha, :created_at, :merged_at, :status)
                              .merge({ base_user: attributes[:repository].owner,
                                      base_repository: attributes[:repository],
                                      head_user: attributes[:repository].owner,
                                      head_repository: attributes[:repository] })
    self.new(pr_attributes).tap do |pull_request|
      issue_attributes = attributes[:issue_attributes]
      pull_request.build_issue(
        repository: attributes[:repository],
        user: attributes[:user],
        title: issue_attributes[:title],
        body: issue_attributes[:body],
        number: issue_attributes[:number],
        created_at: attributes[:created_at],
        closed_at: attributes[:closed_at],
        state: attributes[:closed_at].nil? ? "open" : "closed",
        milestone: issue_attributes[:milestone]
      )
    end
  end

  def type
    "PullRequest"
  end
end
