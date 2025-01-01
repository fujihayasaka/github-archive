# typed: true
# frozen_string_literal: true

class DeletedIssue < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repository)
  belongs_to :deleted_by, class_name: "User"

  validates :repository, presence: true
  validates :number, presence: true, uniqueness: { scope: :repository_id }
  validates :deleted_by, presence: true
  validates :old_issue_id, presence: true

  def self.delete_issue(issue, deleter:)
    transaction do
      create!(repository: issue.repository, deleted_by: deleter, number: issue.number, old_issue_id: issue.id)
      GlobalInstrumenter.instrument("issue.deleted", { repository: issue.repository, actor: deleter, issue: issue })
      issue.destroy
    end
  end
end
