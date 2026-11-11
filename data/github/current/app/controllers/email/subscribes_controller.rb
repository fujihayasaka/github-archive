# typed: true
# frozen_string_literal: true

class Email::SubscribesController < ApplicationController
  # Because this controller doesn't deal with protected organization resources,
  # we can safely `skip_before_action` its actions.
  skip_before_action :perform_conditional_access_checks, only: [:update, :create] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  def update
    if "unsubscribe" == params[:kind]
      destroy
    else
      create
    end
  end

  def create
    name = params[:name]
    kind = params[:kind]

    return render_404 if !name || !kind

    @subscription = NewsletterSubscription.subscribe(current_user, name, kind)

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "email/explore/subscribe", layout: false
        else
          redirect_to :back
        end
      end
    end
  end

  private

  def destroy
    @subscription = NewsletterSubscription.unsubscribe(params[:token])
    return render_404 if @subscription.blank?

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "email/explore/subscribe", layout: false
        else
          render "email/unsubscribes/show"
        end
      end
    end
  end
end
