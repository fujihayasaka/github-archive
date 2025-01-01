# typed: true
# frozen_string_literal: true

class PullRequestLastPush < ApplicationRecord::Domain::IssuesPullRequests
  extend T::Sig
  include Repositories::Domain::Provider

  belongs_to :pull_request, required: true, inverse_of: :last_push
  belongs_to :repository, required: true

  validates :push_id, presence: true, numericality: { only_integer: true }
  validates :head_sha, presence: true, format: { with: /\A[a-f0-9]{40}\Z/, message: "should be a full commit SHA" }

  sig { returns(T.nilable(Repositories::IPush)) }
  def push
    return @push if defined? @push

    repo_id = T.must(pull_request&.head_repository_id)
    @push = repositories_domain.pushes.by_id_and_repo_id(id: push_id, repository_id: repo_id)
  end

  sig { params(push_id: Integer).void }
  def push_id=(push_id)
    remove_instance_variable :@push if defined? @push
    super
  end
end
