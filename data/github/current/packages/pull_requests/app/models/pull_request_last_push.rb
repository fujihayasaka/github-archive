# typed: true
# frozen_string_literal: true

class PullRequestLastPush < ApplicationRecord::Domain::IssuesPullRequests
  include Repositories::Domain::Provider

  belongs_to :pull_request, required: true, inverse_of: :last_push
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain required: true

  validates :push_id, presence: true, numericality: { only_integer: true }
  validates :head_sha, presence: true, format: { with: /\A[a-f0-9]{40}\Z/, message: "should be a full commit SHA" }

  sig { returns(T.nilable(Repositories::Push)) }
  def push
    return @push if defined? @push

    repo_id = T.must(pull_request&.head_repository_id)
    @push = repositories_domain.pushes.by_id_and_repo_id(id: push_id, repository_id: repo_id)

    if @push.nil?
      # We don't delete Push records, so something went wrong if we can't find it. Maybe remove this check in the future.
      GitHub.logger.warn("Last reviewable push missing", {
        "gh.push_id": push_id,
        "gh.head_sha": head_sha,
        "gh.pull_request.id": pull_request_id,
        "gh.pull_request.number": pull_request&.number,
        "gh.pull_request.head_repo.id": pull_request&.head_repository_id,
        "gh.pull_request.base_repo.id": pull_request&.base_repository_id,
        "gh.pull_request_base_ref": pull_request&.base_ref,
        })
    end

    @push
  end

  sig { params(push_id: Integer).void }
  def push_id=(push_id)
    remove_instance_variable :@push if defined? @push
    super
  end
end
