# typed: true
# frozen_string_literal: true

class Dependabot::DependabotAlertsOneClickUnsubscriptionsController < ApplicationController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Dependabot::DependabotAlertsOneClickUnsubscriptionsController#create"
  ]

  layout false

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Mysql2, only: [:create]

  # We can't provide a CSFR token for this POST request
  # because it is done by Email clients, that is why we need to disable CSFR checks
  skip_before_action :verify_authenticity_token, only: [:create]

  # bypass all CAP policies because unsubscribe requests are originated by emails and use token based authentication
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  sig { void }
  def create
    if params["List-Unsubscribe"] != "One-Click"
      return render plain: "Invalid One Click POST request", status: :bad_request
    end

    case params[:email_type]
    when "vulnerability-digest"
      if NewsletterSubscription.unsubscribe(params[:token])
        head :ok
      else
        render plain: "Invalid token", status: :forbidden
      end
    when "new-vulnerabilities"
      user, _ = GitHub.newsies.user_and_id_from_token(:unsubscribe_vulnerability_alerts, params[:token])
      return render plain: "Invalid token", status: :forbidden unless user

      if Notifications::Settings.disable_vulnerability_email(user)
        head :ok
      else
        render plain: "Error unsubscribing from list", status: :internal_server_error
      end
    end
  end
end
