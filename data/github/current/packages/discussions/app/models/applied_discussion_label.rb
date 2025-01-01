# typed: true
# frozen_string_literal: true

class AppliedDiscussionLabel < ApplicationRecord::Domain::Discussions
  belongs_to :discussion, inverse_of: :applied_discussion_labels
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :label, inverse_of: :applied_discussion_labels

  validates :discussion, :repository, :label, presence: true
  validate :consistent_repository_id

  before_validation :set_repository_id, on: :create, unless: :repository_id

  private

  sig { void }
  def set_repository_id
    repo_id = label&.repository_id
    return unless repo_id
    self.repository_id = repo_id
  end

  sig { void }
  def consistent_repository_id
    discussion_repository_id = discussion&.repository_id
    label_repository_id = label&.repository_id
    if repository_id != discussion_repository_id || repository_id != label_repository_id
      errors.add(:repository_id, "must be consistent with discussion and label")
    end
  end
end
