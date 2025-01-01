# typed: true
# frozen_string_literal: true
class UserStafftoolsRole < ApplicationRecord::Ballast
  include Instrumentation::Model
  belongs_to :user
  validates :user, presence: true
  validate :staff_user
  belongs_to :stafftools_role
  validates :stafftools_role, presence: true
  validates_uniqueness_of :stafftools_role_id, scope: :user_id,
    message: "Role already assigned to user"

  after_create_commit :log_role_assignment
  after_destroy_commit :log_role_removal

  private

  def staff_user
    return unless user
    unless T.must(user).site_admin?
      errors.add :user_staff_admin, "User #{T.must(user).login} must be a site admin to be assigned stafftools roles"
    end
  end

  def log_role_assignment
    GitHub.instrument "stafftools_role.assignment", event_payload
  end

  def log_role_removal
    GitHub.instrument "stafftools_role.removal", event_payload
  end

  def event_payload
    {
       user: T.must(user).display_login,
       user_id: T.must(user).id,
       role: T.must(stafftools_role).name,
       role_id: T.must(stafftools_role).id,
     }
  end
end
