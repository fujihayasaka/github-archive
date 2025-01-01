# typed: true
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub Copilot.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  # this is triggered when staff blocks a user
  subscribe(::Copilot::Events::ADMINISTRATIVE_BLOCK) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    # we're gonna try to put it in the payload because there is a chance that the user
    # has been blocked/banned/suspended
    access_type = payload.fetch(:access_type, copilot_user.access_type)
    access_type = :UNKNOWN if [:NO_ACCESS, :FEATURE_FLAG_BLOCKED].include?(access_type)

    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
      copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
      block_reason: payload[:block_reason],
      copilot_access_type: access_type,
      state: payload[:state],
    }

    publish(message, schema: "github.copilot.v2.CopilotUserAdministrativeBlock")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # this is triggered when staff unblocks a user
  subscribe(::Copilot::Events::ADMINISTRATIVE_UNBLOCK) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
      copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
      block_reason: "UNBLOCKED - #{payload[:block_reason]}",
      state: payload[:state],
    }

    publish(message, schema: "github.copilot.v2.CopilotUserAdministrativeBlock")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # this is triggered when staff warns a user
  subscribe(::Copilot::Events::ADMINISTRATIVE_WARN) do |payload|
    # this is the only copilot event that has Users, not Copilot::Users
    copilot_user = Copilot::User.new(payload[:user])
    # we're gonna try to put it in the payload because there is a chance that the user
    # has been blocked/banned/suspended
    access_type = payload.fetch(:access_type, copilot_user.access_type)
    access_type = :UNKNOWN if [:NO_ACCESS, :FEATURE_FLAG_BLOCKED].include?(access_type)

    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
      copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
      block_reason: payload[:block_reason],
      copilot_access_type: access_type,
      state: payload[:state],
    }

    publish(message, schema: "github.copilot.v2.CopilotUserAdministrativeBlock")
  end

  # this is triggered when staff changes a free user's quota
  subscribe(::Copilot::Events::FREE_QUOTA_CHANGED_BY_STAFF) do |payload|
    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
      feature: payload[:feature].to_s,
      previous_quota_remaining: payload[:previous_quota_remaining].to_i,
      new_quota_remaining: payload[:new_quota_remaining].to_i,
    }

    publish(message, schema: "github.copilot.v3.CopilotStaffQuotaChanged")
  end

  # this is triggered when staff changes a free user's quota
  subscribe(::Copilot::Events::FREE_UNSUBSCRIBED_BY_STAFF) do |payload|
    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
    }

    publish(message, schema: "github.copilot.v3.CopilotLimitedUserStaffUnsubscribed")
  end


  subscribe(::Copilot::Events::HIDE_COPILOT) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    message = {
      user: serializer.user(payload[:user]),
      access_type: copilot_user.access_type_sku
    }

    publish(message, schema: "github.copilot.v3.CopilotHide")
  end

  subscribe(::Copilot::Events::SHOW_COPILOT) do |payload|
    copilot_user = Copilot::User.new(payload[:user])
    message = {
      user: serializer.user(payload[:user]),
      access_type: copilot_user.access_type_sku
    }

    publish(message, schema: "github.copilot.v3.CopilotShow")
  end

  # this is triggered when staff grants free access to a user
  subscribe(::Copilot::Events::COMPLIMENTARY_ACCESS_GRANTED) do |payload|
    # this is the only copilot event that has Users, not Copilot::Users
    copilot_user = Copilot::User.new(payload[:user])
    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
      copilot_user_details: copilot_user.copilot_user_details,
      free_user_type: serializer.copilot_free_user_type(payload[:free_user_type]),
      complimentary_access_duration: payload[:complimentary_access_duration],
      complimentary_access_reason_explanation: payload[:complimentary_access_reason_explanation],
    }

    publish(message, schema: "github.copilot.v1.CopilotComplimentaryAccessGrantedEvent")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # this is triggered when staff removes free access from a user
  subscribe(::Copilot::Events::COMPLIMENTARY_ACCESS_REMOVED) do |payload|
    # this is the only copilot event that has Users, not Copilot::Users
    copilot_user = Copilot::User.new(payload[:user])
    message = {
      staff_actor: serializer.user(payload[:staff_actor]),
      user: serializer.user(payload[:user]),
      copilot_user_details: copilot_user.copilot_user_details,
      free_user_type: serializer.copilot_free_user_type(payload[:free_user_type]),
      complimentary_access_removal_explanation: payload[:complimentary_access_removal_explanation],
    }

    publish(message, schema: "github.copilot.v1.CopilotComplimentaryAccessRemovedEvent")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # this is triggered when an Editor Notification is sent in the API
  subscribe(::Copilot::Events::EDITOR_NOTIFICATION) do |payload|
    copilot_user = payload[:copilot_user] # this is ALWAYS a Copilot::User - thanks Sorbet!

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(copilot_user.user_object),
      copilot_user_details: copilot_user.copilot_user_details,
      notification_event_type: payload[:notification_event_type],
      notification_event_name: payload[:notification_event_name],
      editor_version: payload[:editor_version],
      editor_plugin_version: payload[:editor_plugin_version],
    }

    publish(message, schema: "github.copilot.v1.CopilotEditorNotificationEvent")
  end

  # This is triggered by the background job for Free Users
  subscribe(::Copilot::Events::FREE_USER_EVENT) do |payload|
    copilot_user = payload[:copilot_user]

    message = {
      user: serializer.user(copilot_user.user_object),
      copilot_user_details: copilot_user.copilot_user_details,
      event_type: payload[:free_user_event_type], # we don't convert this because we're only sending a symbol here
    }

    publish(message, schema: "github.copilot.v1.CopilotFreeUserEvent")
  end

  # This is triggered when a user changes their Copilot Settings from the copilot settings page
  subscribe(::Copilot::Events::SETTINGS_SAVED) do |payload|
    message = generic_copilot_event(payload)
    message[:old_settings] = serializer.copilot_settings(payload[:old_settings])
    message[:new_settings] = serializer.copilot_settings(payload[:new_settings])
    message.delete(:copilot_analytics)

    publish(message, schema: "github.copilot.v1.CopilotSettingsSaved")
    copilot_user = payload[:copilot_user]
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # This is triggered when a user confirms their payment
  subscribe(::Copilot::Events::SIGNUP_CONFIRMED_PAYMENT) do |payload|
    message = generic_copilot_event(payload)

    publish(message, schema: "github.copilot.v1.CopilotSignupConfirmedPayment")
  end

  # This is triggered when a user lands on the free user page
  subscribe(::Copilot::Events::SIGNUP_FREE_PAGE_VIEW) do |payload|
    message = generic_copilot_event(payload)

    publish(message, schema: "github.copilot.v1.CopilotSignupFreePageViewed")
  end

  # This is triggered when a user creates a Free Subscription
  subscribe(::Copilot::Events::SIGNUP_FREE_SUBSCRIPTION_CREATED) do |payload|
    message = generic_copilot_event(payload)

    publish(message, schema: "github.copilot.v1.CopilotSignupFreeSubscriptionCreated")
    copilot_user = payload[:copilot_user]
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # This is triggered when a user lands on the signup page
  subscribe(::Copilot::Events::SIGNUP_PAGE_VIEW) do |payload|
    message = generic_copilot_event(payload)

    publish(message, schema: "github.copilot.v1.CopilotSignupPageViewed")
  end

  # This is triggered when a user chooses a plan during signup
  subscribe(::Copilot::Events::SIGNUP_PLAN_CHOSEN) do |payload|
    message = generic_copilot_event(payload)
    message[:chosen_plan] = serializer.copilot_subscription_plan(payload[:chosen_plan])
    publish(message, schema: "github.copilot.v1.CopilotSignupPlanChosen")
  end

  # This is triggered when a user chooses a plan during signup
  subscribe(::Copilot::Events::SIGNUP_SAVED_ADDRESS) do |payload|
    message = generic_copilot_event(payload)
    publish(message, schema: "github.copilot.v1.CopilotSignupSavedAddress")
  end

  # This is triggered when a user configures their settings during signup
  subscribe(::Copilot::Events::SIGNUP_SETTINGS_SAVED) do |payload|
    message = generic_copilot_event(payload)
    message[:old_settings] = serializer.copilot_settings(payload[:old_settings])
    message[:new_settings] = serializer.copilot_settings(payload[:new_settings])

    publish(message, schema: "github.copilot.v1.CopilotSignupSettingsSaved")
  end

  # This is triggered when a user signs up for a Copilot Subscription
  subscribe(::Copilot::Events::SIGNUP_SUBSCRIPTION_CREATED) do |payload|
    message = generic_copilot_event(payload)
    message[:copilot_subscription_plan] = serializer.copilot_subscription_plan(payload[:copilot_subscription_plan])
    message[:trial_length] = payload[:trial_length]

    publish(message, schema: "github.copilot.v1.CopilotSignupSubscriptionCreated")
    copilot_user = payload[:copilot_user]
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # This is triggered when a user cancels their Copilot subscription
  subscribe(::Copilot::Events::SUBSCRIPTION_CANCELLED) do |payload|
    copilot_user = payload[:copilot_user]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(copilot_user.user_object),
      copilot_user_details: copilot_user.copilot_user_details,
      in_trial: payload[:in_trial],
      subscription_plan: serializer.copilot_subscription_plan(payload[:subscription_plan]),
    }

    publish(message, schema: "github.copilot.v1.CopilotSubscriptionCancelled")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # TODO: This requires changes to billing to support
  # This is triggered when a user changes their Copilot subscription plan
  subscribe(::Copilot::Events::SUBSCRIPTION_DURATION_CHANGED) do |payload|
    copilot_user = payload[:copilot_user]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(copilot_user.user_object),
      copilot_user_details: copilot_user.copilot_user_details,
      in_trial: payload[:in_trial],
      old_subscription_plan: serializer.copilot_subscription_plan(payload[:old_subscription_plan]),
      new_subscription_plan: serializer.copilot_subscription_plan(payload[:new_subscription_plan]),
    }

    publish(message, schema: "github.copilot.v1.CopilotSubscriptionDurationChanged")
  end

  # This is triggered when a user is denied a token
  subscribe(::Copilot::Events::TOKEN_FAILURE) do |payload|
    copilot_user = payload[:copilot_user]
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(copilot_user.user_object),
      failure_reason: payload[:failure_reason],
      editor_version: payload[:editor_version],
      editor_plugin_version: payload[:editor_plugin_version],
      copilot_user_details: copilot_user.copilot_user_details,
    }

    publish(message, schema: "github.copilot.v0.CopilotTokenFailure")
  end

  # This is triggered when a user generates a token
  subscribe(::Copilot::Events::TOKEN_GENERATED) do |payload|
    copilot_user = payload[:copilot_user]
    organization_list = payload[:organization_list]
    org_list = organization_list.present? ? organization_list.join(",") : nil
    source = payload.fetch(:source, "token_generation")
    access_type = payload[:copilot_access_type]

    message = {
      actor_analytics_tracking_id: copilot_user.user_object.analytics_tracking_id,
      actor: serializer.user(copilot_user.user_object),
      copilot_access_type: access_type,
      copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
      editor_plugin_version: payload[:editor_plugin_version],
      editor_version: payload[:editor_version],
      expires_at: payload[:expires_at],
      free_enterprise_organization_name: payload[:free_enterprise_organization_name],
      organization_analytics_tracking_ids: org_list,
      other_free_access_type: nil,
      partner_organization_name: payload[:partner_organization_name],
      quota_details: copilot_user.quota_details,
      request_context: serializer.request_context(GitHub.context.to_hash),
      source: source,
    }

    publish(message, schema: "github.copilot.v0.CopilotTokenGenerated")
  end

  # This is triggered when a user's subscription converts to paid
  subscribe(::Copilot::Events::TRIAL_SUBSCRIPTION_CONVERTS) do |payload|
    copilot_user = payload[:copilot_user]

    message = {
      user: serializer.user(copilot_user.user_object),
      copilot_user_details: copilot_user.copilot_user_details,
      subscription_plan: serializer.copilot_subscription_plan(payload[:subscription_plan]),
    }

    publish(message, schema: "github.copilot.v1.CopilotSubscriptionTrialConvertsToPaid")
    copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
  end

  # This is triggered when a user lands on the code referencing page
  subscribe(::Copilot::Events::CODE_REFERENCING_PAGE_VIEW) do |payload|
    copilot_user = payload[:copilot_user]

    message = {
      user: serializer.user(copilot_user.user_object),
      request_context: serializer.request_context(GitHub.context.to_hash),
      editor_version: payload[:editor_version],
      fingerprint: payload[:fingerprint]
    }

    publish(message, schema: "github.copilot.v2.CopilotCodeReferencingPageViewed")
  end

  subscribe(::Copilot::Events::LIMITED_USER_SUBSCRIBED) do |payload|
    message = generic_copilot_event(payload)
    publish(message, schema: "github.copilot.v3.CopilotLimitedUserSubscribed")
  end

  subscribe(::Copilot::Events::COPILOT_PRO_SUBSCRIPTION_CREATED) do |payload|
    copilot_user = payload[:copilot_user]
    message = {
      user: serializer.user(copilot_user.user_object),
      billing_frequency: payload[:billing_frequency]
    }
    publish(message, schema: "github.copilot.v3.CopilotProSubscribed")
  end

  subscribe(::Copilot::Events::COPILOT_PRO_PLUS_SUBSCRIPTION_CREATED) do |payload|
    copilot_user = payload[:copilot_user]
    message = {
      user: serializer.user(copilot_user.user_object),
      billing_frequency: payload[:billing_frequency]
    }
    publish(message, schema: "github.copilot.v3.CopilotProPlusSubscribed")
  end

  subscribe(::Copilot::Events::COPILOT_PRO_PLUS_SUBSCRIPTION_DOWNGRADED) do |payload|
    copilot_user = payload[:copilot_user]
    message = {
      user: serializer.user(copilot_user.user_object),
      billing_frequency: payload[:billing_frequency]
    }
    publish(message, schema: "github.copilot.v3.CopilotProPlusSubscriptionDowngraded")
  end

  # An event is triggered when the billable customer is changed
  subscribe(::Copilot::Events::COPILOT_BILLABLE_CUSTOMER_CHANGE) do |payload|
    message = {
      user_id: payload[:user_id],
      billable_customer_id: payload[:billable_customer_id]
    }

    publish(message, schema: "github.copilot.v3.CopilotLicenseChange")
  end

  def generic_copilot_event(payload)
    T.bind(self, Hydro::EventForwarder)

    copilot_user = payload[:copilot_user]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: copilot_user ? serializer.user(copilot_user.user_object) : nil,
      copilot_analytics: {
        utm_source: payload[:utm_source],
        utm_medium: payload[:utm_medium],
        utm_campaign: payload[:utm_campaign],
        utm_term: payload[:utm_term],
        utm_content: payload[:utm_content],
      },
      copilot_user_details: copilot_user ? copilot_user.copilot_user_details : nil,
    }
    message
  end
end
