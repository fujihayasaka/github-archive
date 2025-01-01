# typed: true
# frozen_string_literal: true

class Email::OptinsController < ApplicationController
  skip_before_action :perform_conditional_access_checks, only: [:show, :create] # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :login_required, except: [:show]

  layout "site"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  REQUIRED_SCOPE = "EmailOptin:marketing-emails"

  def show
    if user = user_from_email_token
      ActiveRecord::Base.connected_to(role: :writing) do
        NewsletterPreference.set_to_marketing user: user, signup: false, source: "opt-in"
      end
      render "email/optins/create"
    elsif logged_in?
      render "email/optins/show"
    else
      redirect_to_login email_optin_path
    end
  end

  def create
    NewsletterPreference.set_to_marketing user: current_user, signup: false, source: "opt-in"
    render "email/optins/create"
  end

  private

  def stateless_request?
    user_from_email_token || super
  end

  def user_from_email_token
    return if action_name != "show"
    User.authenticate_with_signed_auth_token token: params[:token],
                                             scope: REQUIRED_SCOPE
  end
end
