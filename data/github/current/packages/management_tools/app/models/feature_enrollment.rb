# typed: true
# frozen_string_literal: true

class FeatureEnrollment < ApplicationRecord::Collab
  self.ignored_columns = %w(user_id)
  include Instrumentation::Model

  # These map to the Action field in the github.v1.FeatureEnrollmentEvent hydro-schema
  ENROLLED_ACTION = "ENROLLED"
  UNENROLLED_ACTION = "UNENROLLED"

  belongs_to :feature
  belongs_to :enrollee, polymorphic: true
  belongs_to :last_actor, class_name: "User"

  validates :enrollee, presence: true
  validates :feature, presence: true
  validate :validate_enrollee_is_user

  scope :enrolled, -> { where(enrolled: true) }
  scope :unenrolled, -> { where(enrolled: false) }
  scope :for_enrollee, -> (enrollee) { where(enrollee: enrollee) }

  before_validation :set_last_actor, on: [:create, :update]

  after_commit :instrument_enrollment, on: [:create, :update], if: :enrolled?
  after_commit :instrument_unenrollment, on: [:create, :update], if: :unenrolled?

  def self.set_for(feature:, enrollee:, enrolled:)
    enrollment = create_with(enrolled: enrolled).create_or_find_by(feature: feature, enrollee: enrollee)
    enrollment.update(enrolled: enrolled) if enrollment.enrolled != enrolled
    enrollment
  end

  def enroll
    update(enrolled: true)
  end

  def unenroll
    update(enrolled: false)
  end

  def unenrolled?
    !enrolled?
  end

  private

  def validate_enrollee_is_user
    if !enrollee.is_a?(User) || enrollee.organization? || enrollee.bot?
      errors.add(:enrollee, "must be a valid User")
    end
  end

  def set_last_actor
    self.last_actor = User.find_by(id: GitHub.context[:actor_id])
  end

  def instrument_unenrollment
    instrument :unenrolled
  end

  def instrument_enrollment
    instrument :enrolled
  end

  def event_payload
    {
      toggleable_feature: feature,
      feature_enrollment_id: self.id,
      enrollee_id: enrollee_id,
      enrollee_type: enrollee_type,
      actor: last_actor,
      enrolled: enrolled,
    }
  end
end
