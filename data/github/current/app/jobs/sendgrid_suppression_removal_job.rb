# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class SendgridSuppressionRemovalJob < ApplicationJob
  queue_as :sendgrid_suppression_removal

  retry_on_dirty_exit
  retry_on GitHub::Sendgrid::Error

  def perform(email_id)
    user_email = UserEmail.find_by_id(email_id)
    return if user_email.nil?

    begin
      GitHub::Sendgrid.new(user_email).remove_bounce_suppression
    rescue GitHub::Sendgrid::Error => exception
      Failbot.report(exception, email_id: email_id)
      raise
    end
  end
end
