# typed: true
# frozen_string_literal: true

# Public: This is the module namespace for the legacy GitHub Notifications system.
# See README.md for the big overview.
module Newsies
  autoload :ActiveRecordSettingsStore, "newsies/active_record_settings_store"
  autoload :ApproximateCount, "newsies/approximate_count"
  autoload :Authentication, "newsies/authentication"
  autoload :Comment, "newsies/objects/comment"
  autoload :CommonSubscriptionHelper, "newsies/common_subscription_helper"
  autoload :DeliveryLogger, "newsies/delivery_logger"
  autoload :DeliveryOptions, "newsies/delivery_options"
  autoload :Emails, "newsies/emails"
  autoload :Error, "newsies/error"
  autoload :List, "newsies/objects/list"
  autoload :MarkAllNotificationsFromQueryJobStatus, "newsies/mark_all_notifications_from_query_job_status"
  autoload :Object, "newsies/object"
  autoload :Options, "newsies/options"
  autoload :PageWithPreviousAndNextFlags, "newsies/page_with_previous_and_next_flags"
  autoload :Reasons, "newsies/reasons"
  autoload :Response, "newsies/response"
  autoload :Responses, "newsies/responses"
  autoload :Service, "newsies/service"
  autoload :Settings, "newsies/settings"
  autoload :SettingsSerializer, "newsies/settings_serializer"
  autoload :SettingsStore, "newsies/settings_store"
  autoload :SloHelper, "newsies/slo_helper"
  autoload :SubscriberSet, "newsies/subscriber_set"
  autoload :Subscription, "newsies/subscription"
  autoload :Thread, "newsies/objects/thread"
  autoload :ThreadSubscribeOptions, "newsies/thread_subscribe_options"
  autoload :ThreadSubscriptionManager, "newsies/thread_subscription_manager"
  autoload :TrackedDeliveries, "newsies/tracked_deliveries"
  autoload :Web, "newsies/managers/web"

  NOTIFICATIONS_PER_PAGE = 50

  HANDLER_EMAIL = "email".freeze
  HANDLER_WEB = "web".freeze
  HANDLERS = Set.new([HANDLER_WEB, HANDLER_EMAIL]).freeze

  SETTINGS_GROUP_PARTICIPATING = "participating".freeze
  SETTINGS_GROUP_SUBSCRIBED = "subscribed".freeze
  SETTINGS_GROUPS = Set.new([SETTINGS_GROUP_PARTICIPATING, SETTINGS_GROUP_SUBSCRIBED]).freeze

  SETTINGS_EMAILS = "emails".freeze
  SETTINGS_EMAILS_GLOBAL = "global".freeze

  SETTINGS_AUTO_SUBSCRIBE = "auto_subscribe".freeze
  SETTINGS_NOTIFY_OWN_VIA_EMAIL = "notify_own_via_email".freeze
  SETTINGS_NOTIFY_COMMENT_EMAIL = "notify_comment_email".freeze
  SETTINGS_NOTIFY_PULL_REQUEST_REVIEW_EMAIL = "notify_pull_request_review_email".freeze
  SETTINGS_NOTIFY_PULL_REQUEST_PUSH_EMAIL = "notify_pull_request_push_email".freeze
  SETTINGS_VULNERABILITY_CLI = "vulnerability_cli".freeze
  SETTINGS_VULNERABILITY_WEB = "vulnerability_web".freeze
  SETTINGS_VULNERABILITY_EMAIL = "vulnerability_email".freeze
  SETTINGS_CONTINUOUS_INTEGRATION_WEB = "continuous_integration_web".freeze
  SETTINGS_CONTINUOUS_INTEGRATION_EMAIL = "continuous_integration_email".freeze
  SETTINGS_CONTINUOUS_INTEGRATION_FAILURES_ONLY = "continuous_integration_failures_only".freeze
  SETTINGS_DIRECT_MENTION_MOBILE_PUSH = "direct_mention_mobile_push".freeze
  SETTINGS_ORG_DEPLOY_KEY_EMAIL = "org_deploy_key_email".freeze
end
