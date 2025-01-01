# typed: true
# frozen_string_literal: true

module Notifications
  # This controller handles One-Click unsubscriptions for notifications.
  #
  # One-Click unsubscriptions (RFC-8058) define a set of headers which help
  # senders identify an unsubsription mechansim based on a `POST` request that
  # email clients can use.
  #
  # As opposed to our previous unsubscription mechanisms, One-Click routes are
  # accessed via `POST` only and by a machine, that's why the responses in this
  # controller are text only.
  #
  # Also we make no use of things like cookies or authentication beyond the
  # unsubscribe token as requested by RFC-8058
  #
  # For more information check https://datatracker.ietf.org/doc/html/rfc8058
  class OneClickUnsubscriptionsController < ::ApplicationController
    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
      "Notifications::OneClickUnsubscriptionsController#create"
    ]

    layout false

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsSummaries,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Repositories,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      only: [:create]

    # We can't provide a CSFR token for this POST request
    # because it is done by Email clients, that is why we need to disable CSFR checks
    skip_before_action :verify_authenticity_token, only: [:create]

    # bypass all CAP policies officially instead of via no_tfca
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    def create
      if params["List-Unsubscribe"] != "One-Click"
        return render plain: "Invalid One Click POST request", status: :bad_request
      end

      if !auth&.valid?
        return render plain: "Invalid token", status: :forbidden
      end

      if !resource&.valid?
        return render plain: "List to unsubscribe not found", status: :not_found
      end

      Failbot.push("gh.user.id": auth.user&.id)
      result = unsubscribe_from_link.unsubscribe

      if result.failed?
        Failbot.report(result.error)
        return render plain: "Error unsubscribing from list", status: :internal_server_error
      end

      head :ok
    end

    private

    def auth
      parse_token if @auth.nil?
      @auth
    end

    def resource
      parse_token if @resource.nil?
      @resource
    end

    def parse_token
      @auth, @resource = unsubscribe_from_link.auth, unsubscribe_from_link.resource
    end

    memoize def unsubscribe_from_link
      UnsubscribeFromLink.new(:mute_list, params[:token])
    end
  end
end
