# typed: true
# frozen_string_literal: true

module Audit
  module HttpFluentbit
    HTTP_FLUENTBIT_EVENT_ITEMS = [
      :actor_id,
      :actor,
      :oauth_app_id,
      :action,
      :user_id,
      :user,
      :repo_id,
      :repo,
      :actor_ip,
      :created_at,
      :from,
      :note,
      :org,
      :org_id,
      :data,
    ].freeze

    autoload :Logger, "audit/http_fluentbit/logger"
  end
end
