# typed: true
# frozen_string_literal: true

# All endpoints added for Incident response
class Api::Staff::Emails < Api::Staff::App

  # Find UserEmail(s) (and its corresponding user)
  get "/staff/emails/:email", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/stafftools"
    user_emails = paginate_rel(UserEmail.where("email = ?", params[:email]))

    record_or_404 user_emails

    GitHub::PrefillAssociations.prefill_associations(user_emails, [:email_roles, :user])
    deliver :user_email_hash, user_emails, full: true
  end

  # get all emails associated with a user
  get "/staff/user/:user_id/emails", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/stafftools"
    user = find_user!
    emails = paginate_rel(user.emails.order("id ASC"))
    GitHub::PrefillAssociations.prefill_associations(emails, :email_roles)
    deliver :user_email_hash, emails
  end
end
