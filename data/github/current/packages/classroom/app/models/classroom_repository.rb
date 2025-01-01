# typed: true
# frozen_string_literal: true

class ClassroomRepository < ApplicationRecord::Repositories
  include GitHub::Validations

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  destroy_in_background_with :repository
  belongs_to :user, optional: true
  belongs_to :team, optional: true
  belongs_to :assignment, class_name: "ClassroomAssignment"
  belongs_to :classroom, class_name: "ClassroomClassroom"

  validates :repository, presence: true
  validates :repository, uniqueness: true
  validates :assignment_id, presence: true

  validate :has_user_or_team

  alias_attribute :classroom_assignment_id, :assignment_id

  MAX_STARTER_REPO_DISK_USAGE_IN_KILOBYTES = 1_000_000

  def starter_code_repository
    return nil unless assignment

    assignment&.starter_code_repository
  end

  def has_teacher_toolbox_coupon
    coupons = repository&.owner&.coupons
    return false if coupons&.empty?

    first_coupon = coupons&.first&.code

    Coupon::TEACHER_TOOLBOX.match? first_coupon
  end

  def classroom_name
    classroom&.name
  end

  def assignment_name
    assignment&.name
  end

  def deadline
    assignment&.deadline
  end

  def assignment_type
    assignment&.assignment_type
  end

  def has_autograding?
    assignment&.has_autograding
  end

  def admins
    ClassroomInstructor
      .where(classroom: classroom)
      .pluck(:classroom_user_id)
      .then do |classroom_user_ids|
        User
          .joins(:classroom_user)
          .where(classroom_users: { id: classroom_user_ids })
          .order(:login)
          .pluck(:login)
      end
      .join(",")
  end

  private

  def has_user_or_team
    errors.add(:base, "You must specify a user or a team") if (user && team) || (user.nil? && team.nil?)
  end
end
