# typed: strict
# frozen_string_literal: true

class MoveWorkItem < ApplicationRecord::Collab
  extend T::Sig

  belongs_to :move_work
  belongs_to :resource, polymorphic: true

  validates :resource_type, inclusion: { in: %w(Repository Project MemexProject) }

  # Scopes the polymorphic associtation on resource.
  scope :repositories, -> { where(resource_type: "Repository") }
  scope :projects, -> { where(resource_type: "Project") }

  validates :move_work, presence: true
  validate :resource_is_accessible_by_user

  sig { params(owner: User).returns(ActiveRecord::Relation) }
  def self.started_for_owner(owner)
    joins(:move_work).where(move_work: { origin: owner, state: MoveWork.state_value(:started) })
  end

  private

  sig { void }
  def resource_is_accessible_by_user
    return if resource.blank? || move_work.blank?

    case resource
    when Repository, Project
      errors.add(:resource, "is not adminable by user") unless resource.adminable_by?(T.must(move_work).user)
    end
  end
end
