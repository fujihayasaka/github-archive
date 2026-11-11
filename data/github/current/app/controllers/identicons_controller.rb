# typed: true
# frozen_string_literal: true

class IdenticonsController < ApplicationController

  # Because this controller doesn't deal with protected organization resources,
  # we can safely `skip_before_action` its actions.
  skip_before_action :perform_conditional_access_checks, only: [:show] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    expires_in 1.year, public: true

    identicon_id =
      if params[:user_login]
        User.find_by_login(params[:user_login]).try(:identicon_id)
      elsif (email = params[:email_address])
        User.find_by_email(email).try(:identicon_id)
      else
        params[:id]
      end

    if identicon_id.blank?
      head :not_found
      return
    end

    data = GitHub.cache.fetch("identicon:#{identicon_id}") do
      identicon = Identicon.new(identicon_id)
      identicon.generate_image
    end

    send_data data, type: "image/png", filename: "identicon.png", disposition: "inline"
  end
end
