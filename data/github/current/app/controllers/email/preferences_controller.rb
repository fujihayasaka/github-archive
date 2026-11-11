# typed: true
# frozen_string_literal: true

class Email::PreferencesController < ApplicationController

  # The following actions do not require conditional access checks because
  # they *don't* access protected organization resources.
  skip_before_action :perform_conditional_access_checks, only: [:show, :update] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required, except: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    unless GitHub.email_preference_center_enabled?(current_user)
      redirect_to "/settings/email#preferences" and return
    end

    return render_404 unless logged_in?

    redirect_to settings_email_preferences_path(anchor: "preferences")
  end

  def update
    if params[:resubscribe_id]
      resubscribe
      return
    end

    if params[:unsubscribe_id]
      unsubscribe
      return
    end

    if params[:type] == "marketing"
      NewsletterPreference.set_to_marketing(user: current_user, source: "settings")
    else
      NewsletterPreference.set_to_transactional(user: current_user, source: "settings")
    end

    redirect_to settings_email_preferences_path, notice: "Successfully updated your email preferences."
  end

  private

  def resubscribe
    newsletter_subscription = current_user.newsletter_subscriptions.find_by_id(params[:resubscribe_id])

    if newsletter_subscription && newsletter_subscription.resubscribe
      flash[:notice] = "Successfully resubscribed to the #{newsletter_subscription.human_name.capitalize} email."
    else
      flash[:error] = "Sorry, there was a problem updating that email subscription."
    end

    redirect_to settings_email_preferences_path
  end

  def unsubscribe
    newsletter_subscription = current_user.newsletter_subscriptions.find_by_id(params[:unsubscribe_id])

    if newsletter_subscription && newsletter_subscription.unsubscribe
      flash[:notice] = "Successfully unsubscribed from the #{newsletter_subscription.human_name.capitalize} newsletter."
    else
      flash[:error] = "Sorry, there was a problem updating that email subscription."
    end

    redirect_to settings_email_preferences_path
  end
end
