# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::MicrosoftTradeHelpEmailsController < StafftoolsController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  before_action :ensure_required_fields_exist, only: [:create]
  before_action :clean_body_param, only: [:create]

  sig { void }
  def index
    render "stafftools/trade_compliance/contact"
  end

  sig { void }
  def create
    TradeScreeningMailer.contact_microsoft_trade_help(
      cc_email: params[:cc_email],
      bcc_email: params[:bcc_email],
      subject: params[:subject],
      email_content: params[:email_content]
    ).deliver_later
    flash[:notice] = "An email message has been sent to microsoft trade help."

    redirect_back(fallback_location: stafftools_trade_compliance_microsoft_trade_help_emails_path)
  end

  private

  sig { void }
  def ensure_required_fields_exist
    errors = []
    errors << "You must provide an email for the staff who is contacting microsoft trade support" if params[:cc_email].blank?
    errors << "You must provide a subject for the email" if params[:subject].blank?
    errors << "You must provide a message to send as email to trade help" if params[:email_content].blank?

    flash[:error] = errors.join(", ")
    redirect_back(fallback_location: stafftools_trade_compliance_microsoft_trade_help_emails_path) if errors.any?
  end

  sig { void }
  def clean_body_param
    # Remove the staffer comment line including the newline character if there is one
    params[:email_content].slice!(/.*Staffer can add additional information or remove this line.*[\r\n]?/)
  end
end
