# typed: true
# frozen_string_literal: true

class Email::UnsubscribesController < ApplicationController
  # Because this controller doesn't deal with protected organization resources,
  # we can safely `skip_before_action` its actions.
  skip_before_action :perform_conditional_access_checks, only: [:show] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required
  around_action :select_write_database, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    @subscription = NewsletterSubscription.unsubscribe(params[:token])
    if @subscription.blank?
      redirect_to settings_email_preferences_path(anchor: "preferences")
      return
    end
    render "show"
  end
end
