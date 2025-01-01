# typed: true
# frozen_string_literal: true

require "ghec_admin"

# When a BusinessReportExport manages the metadata for generating exports for
# GHEC admins. Logic for handling the individual reports lives in a class that we look
# up from the `report_type` attribute.
#
# Report classes implement #enqueue and #cleanup methods.
class BusinessReportExport < ApplicationRecord::Domain::Users
  include GitHub::Validations
  include Permissions::Attributes::Wrapper

  self.permissions_wrapper_class = Permissions::Attributes::BusinessReportExport

  REPORT_TYPES = %w[GHECAdmin::EnterpriseDormantUsersExport GHECAdmin::EnterpriseUsersExport]

  belongs_to :actor, class_name: "User"
  belongs_to :owner, polymorphic: true

  validates :actor_id,     presence: true
  validates :owner_id,     presence: true

  # We might allow reports for Organizations later, but only Businesses for now
  validates :owner_type,   presence: true, inclusion: { in: %w(Business) }
  validates :token,        presence: true

  validates :report_type,  presence: true, inclusion: { in: REPORT_TYPES }
  validate :can_only_have_one_report_in_progress, on: :create

  after_initialize :initialize_settings
  before_validation :generate_token, on: :create
  after_commit :enqueue_process_export_results, on: :create
  before_destroy :cleanup

  # This is needed to allow GH staff to run exports on proxima
  def actor
    User.find_by(id: actor_id) || User.unscoped.where(gh_role: "staff").find_by(id: actor_id)
  end

  # The report is a class that implements any of the specific logic

  # Validate that there is not already an object of the same type where the report is still in_progress
  def can_only_have_one_report_in_progress
    if owner.present? && report_type.constantize.in_progress_for_business?(business: owner)
      errors.add(:base, "Only one report can be in progress at a time")
    end
  end

  # for this particular report. We infer the class name directly from the
  # `report_type` field.
  def report
    @report ||= report_type.constantize.new(business_report_export: self)
  end

  # use the token for the url instead of the id
  def to_param
    token
  end

  def is_notified?
    notified_at.present?
  end

  def in_progress?
    !is_complete?
  end

  def is_complete?
    completed_at.present?
  end

  def has_errored?
    errored_at.present?
  end

  def notify_when_complete?
    report.notify_when_complete?
  end

  def notify!
    update(notified_at: Time.now) unless is_notified?
  end

  def complete!
    update(completed_at: Time.now) unless is_complete?
    update(status: "Complete")
  end

  def error!
    update(errored_at: Time.now) unless has_errored?
    update(completed_at: Time.now)
    update(status: "Error")
  end

  def update_status!(current_user_count: 0, total_user_count: 0)
    update(status: "#{current_user_count} / #{total_user_count}")
  end

  private

  # Private: Ensure that settings is always a Hash, even if it's nil.
  #
  # Returns nothing.
  def initialize_settings
    self.settings ||= {}
  end

  # Private: Process the export request in the background and report back to the
  # user when their export is ready for downloading.
  #
  # Returns nothing.
  def enqueue_process_export_results
    report.enqueue
  end

  # Private: The unique token for the export used to download the export.
  #
  # Returns String.
  def generate_token
    self.token = SecureRandom.uuid
  end

  # Defers to the specific report implementation.
  # This will likely delete a remote file on S3.
  def cleanup
    report.cleanup
  end
end
