# typed: true
# frozen_string_literal: true

class PullRequestUpdate < ApplicationRecord::Domain::IssuesPullRequests
  include Repositories::Domain::Provider

  module Reasons
    OPENED = "opened"
    PUSHED = "pushed"
    FORCE_PUSHED = "force_pushed"
    RETARGETED = "retargeted"
    READY_FOR_REVIEW = "ready_for_review"
  end

  enum :reason, {
    Reasons::OPENED => 0,
    Reasons::PUSHED => 1,
    Reasons::FORCE_PUSHED => 2,
    Reasons::RETARGETED => 3,
    Reasons::READY_FOR_REVIEW => 10,
  }

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :pull_request_id }
  validates :base_oid, presence: true, format: { with: /\A[a-f0-9]{40}\Z/, message: "should be a full commit SHA" }
  validates :head_oid, presence: true, format: { with: /\A[a-f0-9]{40}\Z/, message: "should be a full commit SHA" }
  validates :merge_base_oid, presence: true, format: { with: /\A[a-f0-9]{40}\Z/, message: "should be a full commit SHA or blank" }, unless: -> { T.bind(self, PullRequestUpdate); merge_base_oid == "" }

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :pull_request
  belongs_to :actor, class_name: :User
  has_one :review_point, class_name: :PullRequestReviewPoint

  before_validation :set_number, on: :create

  def push
    return @push if defined? @push
    return nil unless push_id
    @push = repositories_domain.pushes.by_id_and_repo_id(repository_id: repository_id, id: T.must(push_id))
  end

  def push_id=(push_id)
    remove_instance_variable :@push if defined? @push
    super
  end

  private

  def set_number
    self.number = T.must(pull_request).updates.order("number DESC").first&.number.to_i + 1
  end
end
