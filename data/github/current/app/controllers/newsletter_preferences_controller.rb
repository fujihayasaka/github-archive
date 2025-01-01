# typed: true
# frozen_string_literal: true

class NewsletterPreferencesController < ApplicationController

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def update
    unless params[:type] == "marketing"
      render_404
      return
    end

    NewsletterPreference.set_to_marketing(user: current_user, source: params[:source])

    redirect_to :back, notice: "Great! We've signed you up to receive newsletters."
  end
end
