# typed: true
# frozen_string_literal: true

class DeletedDiscussion < ApplicationRecord::Domain::Discussions
  belongs_to :repository, required: true
  belongs_to :deleted_by, class_name: "User", required: true

  validates :number, presence: true, uniqueness: { scope: :repository_id }
  validates :old_discussion_id, presence: true

  scope :for_repository, ->(repo) { where(repository_id: repo) }
  scope :with_number, ->(number) { where(number: number) }
  scope :deleted_by, ->(user) { where(deleted_by_id: user) }
end
