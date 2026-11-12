require "zuorest/utils"

module Zuorest::NotificationHistory
  include Utils
  def get_callout_notification_history(params, headers = {})
    get("/v1/notification-history/callout", params:, headers:, url_template: "/v1/notification-history/callout")
  end
end
