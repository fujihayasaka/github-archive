# typed: true
# frozen_string_literal: true

class Stafftools::CopilotBulkUnblocksController < StafftoolsController
  include CopilotBlockHelper

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:index]

  before_action :dotcom_required

  def index
    render "stafftools/copilot_bulk_unblocks/index", locals: {
      formatted_warn_remediation_email: formatted_warn_remediation_email,
      formatted_block_remediation_email: formatted_block_remediation_email,
    }
  end

  def create
    reason = prefix_reason(params[:reason], "unblock")
    logins = params[:logins].split(/[,\s]+/) # support both comma and space-delimited strings

    remediate_warning = params[:email_option] == "remediate-warning"
    remediate_block = params[:email_option] == "remediate-block"

    unblock_payment_method = !!params[:unblock_payment_method]

    # edit reason to keep a record of remediation emails sent
    if remediate_warning
      reason += " - warn remedial email sent"
    elsif remediate_block
      reason += " - block remedial email sent"
    else
      reason += " - no remedial email sent"
    end

    users = User.where(login: logins)
    logins_without_users = logins - users.map(&:login)

    if logins_without_users.any?
      flash[:error] = "Could not find users with logins: #{logins_without_users.join(", ")}"
    end

    users.each do |u|
      # unblock account and payment method if specified
      Copilot::User.new(u).administrative_unblock!(current_user, reason, unblock_payment_method: unblock_payment_method)

      # send remediation email if requested
      if remediate_warning
        remediate_with_email_via_sire(u, reason, Copilot.warn_remediation_email)
      elsif remediate_block
        remediate_with_email_via_sire(u, reason, Copilot.block_remediation_email)
      end
    end

    if users.any?
      flash[:notice] = "Unblocked users with logins: #{users.map(&:login).join(", ")}. "

      if remediate_warning
        flash[:notice] += "Sent a warning remediation email to each user."
      elsif remediate_block
        flash[:notice] += "Sent a block remediation email to each user."
      end
    end

    index
  end

  sig { params(user: User, reason: String, email_template: String).void }
  def remediate_with_email_via_sire(user, reason, email_template) # rubocop:todo GitHub/UseRestfulActions
    reference_number = SecureRandom.uuid
    GitHub.logger.info(
      "Sending a remedial email to user via SIRE",
      "gh.copilot.email.reason" => reason,
      "gh.user.login" => user,
      "gh.actor.login" => current_user,
      "gh.copilot.email.reference_number" => reference_number,
    )

    # create actions
    incident_response_user_actions = {
      users: [{ id: user.id }],
      staffnote: "notifying user of error in previous Copilot access notification",
      notify: {
        from: "support@githubsupport.com",
        subject: "Correction: Regarding Your Copilot Access",
        template: email_template
      }
    }

    SecurityIncidentResponseJob.perform_later(
      actor: current_user,
      id: reference_number,
      incident_responses: [
        incident_response_user_actions
      ]
    )
  end

  sig { returns(ActiveSupport::SafeBuffer) }
  def formatted_warn_remediation_email # rubocop:todo GitHub/UseRestfulActions
    ActiveSupport::SafeBuffer.new(Copilot.warn_remediation_email.gsub("\n\n", "<p>").gsub("\n", "<br>"))
  end

  sig { returns(ActiveSupport::SafeBuffer) }
  def formatted_block_remediation_email # rubocop:todo GitHub/UseRestfulActions
    ActiveSupport::SafeBuffer.new(Copilot.block_remediation_email.gsub("\n\n", "<p>").gsub("\n", "<br>"))
  end
end
