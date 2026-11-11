# typed: true
# frozen_string_literal: true

module Notifyd
  class EmailLinkTracking
    AUTH_SCOPE = "LinkTracking".freeze

    def initialize(token)
      @token = token
    end

    attr_reader :token

    def track
      notifyd = ::Notifyd::TokenHandler.new(AUTH_SCOPE, token)

      auth, resource = notifyd.prepare
      return true if auth.valid? && log_email_link_click(auth, resource)

      GitHub.dogstats.increment("notifyd.link_click_tracking.failed", tags: ["reason:invalid_token"])
      false
    end

    def log_email_link_click(auth, resource)
      newsies_list = Newsies::List.to_object(resource&.thread&.notifications_list)
      newsies_thread = Newsies::Thread.to_object(resource&.thread)

      GlobalInstrumenter.instrument(
        "notifications.user_action",
        user: auth&.user,
        list_type: newsies_list&.type,
        list_id: newsies_list&.id,
        thread_type: newsies_thread&.type,
        thread_id: newsies_thread&.id,
        handler: :EMAIL,
        action: :LINK_CLICK,
        metadata: {
          "event" => "footer_click",
          "action" => AUTH_SCOPE,
          "service" => "notifyd",
          "is_pull_request" => (resource&.thread.try(:pull_request_id).present?).to_s,
          "subject_type" => resource&.try(:subject_type).to_s
        }
      )
      true
    end
  end
end
