# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to user Profile.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("profile.update") do |payload|
    current_profile = payload[:current_profile]
    previous_profile = payload[:previous_profile]

    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_actor = serializer.user(payload[:actor])
    serialized_current_profile = serializer.profile(current_profile)
    serialized_previous_social_accounts = previous_profile.social_accounts.map do |account|
      serializer.social_account(account)
    end
    serialized_current_social_accounts = current_profile.social_accounts.map do |account|
      serializer.social_account(account)
    end

    message = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      previous_profile: serializer.profile(previous_profile),
      current_profile: serialized_current_profile,
      spamurai_form_signals: serialized_spamurai_form_signals,
      changed_attribute_names: payload[:changed_attribute_names],
      previous_social_accounts: serialized_previous_social_accounts,
      current_social_accounts: serialized_current_social_accounts,
    }.merge(serializer.profile_specimen_data_fields(current_profile))

    publish(message, schema: "github.v1.ProfileUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    if current_profile.bio != previous_profile.bio
      user_generated_content_msg = {
        request_context: serialized_request_context,
        spamurai_form_signals: serialized_spamurai_form_signals,
        action_type: :UPDATE,
        content_type: :PROFILE_BIO,
        actor: serialized_actor,
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.ProfileUpdate"),
        content_database_id: serialized_current_profile[:id],
        content_global_relay_id: current_profile.global_relay_id,
        content_created_at: serialized_current_profile[:created_at],
        content_updated_at: serialized_current_profile[:updated_at],
        title: serializer.specimen_data(current_profile.user.display_name),
        content: serializer.specimen_data(current_profile.bio),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: serialized_actor,
        repository: nil,
        content_visibility: :PUBLIC,
        content_url: serializer.url_for_model(current_profile),
      }

      publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    end

    if current_profile.pronouns != previous_profile.pronouns
      user_generated_content_msg = {
        request_context: serialized_request_context,
        spamurai_form_signals: serialized_spamurai_form_signals,
        action_type: :UPDATE,
        content_type: :PRONOUN,
        actor: serialized_actor,
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.ProfileUpdate"),
        content_database_id: serialized_current_profile[:id],
        content_global_relay_id: current_profile.global_relay_id,
        content_created_at: serialized_current_profile[:created_at],
        content_updated_at: serialized_current_profile[:updated_at],
        title: serializer.specimen_data(current_profile.user.display_name),
        content: serializer.specimen_data(current_profile.pronouns),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: serialized_actor,
        repository: nil,
        content_visibility: :PUBLIC,
        content_url: serializer.url_for_model(current_profile),
      }

      publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    end

    payload.fetch(:created_social_accounts, []).each do |account|
      creation_message = {
        request_context: serialized_request_context,
        actor: serialized_actor,
        spamurai_form_signals: serialized_spamurai_form_signals,
        social_account: serializer.social_account(account),
      }

      publish(creation_message, schema: "github.v1.SocialAccountCreate")
    end

    payload.fetch(:destroyed_social_accounts, []).each do |account|
      destruction_message = {
        request_context: serialized_request_context,
        actor: serialized_actor,
        social_account: serializer.social_account(account),
      }

      publish(destruction_message, schema: "github.v1.SocialAccountDestroy")
    end
  end

  subscribe("profile_picture.update") do |payload|
    request_context = serializer.request_context(GitHub.context.to_hash)
    avatar = serializer.avatar(payload[:avatar])
    user = serializer.user(payload[:actor])

    next unless avatar && user

    message = {
      request_context: request_context,
      actor: user,
      avatar: avatar,
    }
    image_scan_message = {
      request_context: request_context,
      actor: user,
      upload_ip: serializer.ip_address(GitHub.context[:actor_ip]),
      image_model: {
        id: avatar[:id],
        created_at: avatar[:created_at],
        updated_at: avatar[:updated_at],
        uploader_id: user[:id],
        uploader_login: user[:display_login],
        type: :AVATAR,
        size: avatar[:size],
        content_type: avatar[:content_type],
        canonical_url: "https://media.githubusercontent.com/avatars/#{avatar[:id]}",
      },
    }

    publish(message, schema: "github.v1.PrimaryAvatarUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    publish(image_scan_message, schema: "github.trust_safety.v0.ImageScan")
  end

  subscribe("profile_pin.created") do |payload|
    message = { position: payload[:position], internal_view: payload[:internal_view] }
    message[:repository_id] = payload[:repository_id] if payload[:repository_id]
    message[:gist_id] = payload[:gist_id] if payload[:gist_id]
    message[:user] = serializer.user(payload[:user]) if payload[:user]
    if payload[:organization]
      message[:organization] = serializer.organization(payload[:organization])
    end

    publish(message, schema: "github.v1.ProfilePinCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("profile_pin.deleted") do |payload|
    message = { position: payload[:position], internal_view: payload[:internal_view] }
    message[:repository_id] = payload[:repository_id] if payload[:repository_id]
    message[:gist_id] = payload[:gist_id] if payload[:gist_id]
    message[:user] = serializer.user(payload[:user]) if payload[:user]
    if payload[:organization]
      message[:organization] = serializer.organization(payload[:organization])
    end

    publish(message, schema: "github.v1.ProfilePinDestroy", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("user_profile.page_view") do |payload|
    message = {
      profile_user: serializer.user(payload.fetch(:profile_user)),
      profile_viewer: serializer.user(payload.fetch(:profile_viewer)),
      request_context: serializer.request_context(GitHub.context.to_hash),
      has_organization_memberships: payload.fetch(:has_organization_memberships),
      scoped_org_id: payload.fetch(:scoped_org_id),
      selected_tab: payload.fetch(:selected_tab),
      profile_readme_rendered: payload.fetch(:profile_readme_rendered, false),
    }

    publish(message, schema: "github.v1.UserProfileView", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("user_profile.repositories.page_view") do |payload|
    message = {
      profile_user: serializer.user(payload.fetch(:profile_user)),
      profile_viewer: serializer.user(payload.fetch(:profile_viewer)),
      request_context: serializer.request_context(GitHub.context.to_hash),
      is_organization: payload.fetch(:is_organization),
      selected_sort: payload.fetch(:selected_sort),
    }

    publish(message, schema: "github.v1.UserProfileRepositoriesView", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.user_profile.highlights_click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      scoped_org_id: payload.fetch(:scoped_org_id),
      client_timestamp: payload[:client][:timestamp].try(:to_i),
      server_timestamp: Time.zone.now,
      target_url: payload.fetch(:target_url),
      target_type: payload.fetch(:target_type),
      originating_request_id: payload.fetch(:originating_request_id),
    }

    publish(message, schema: "github.v1.UserProfileHighlightsClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.user_profile.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      profile_user: serializer.user(User.find(payload.fetch(:profile_user_id))),
      client_timestamp: payload[:client][:timestamp].try(:to_i),
      server_timestamp: Time.zone.now,
      originating_request_id: payload.fetch(:originating_request_id),
      target: payload.fetch(:target),
    }

    publish(message, schema: "github.v1.UserProfileClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("profile_activity_tab.visibility_changed") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      visibility: payload[:visibility].upcase.to_sym,
    }

    publish(message, schema: "github.v1.ProfileActivityTabVisibilityChange")
  end

  subscribe("profile_activity_event.visibility_changed") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      visibility: payload[:visibility].upcase.to_sym,
      event_id: payload[:event_id],
    }

    publish(message, schema: "github.feeds.v0.ProfileActivityEventVisibilityChange")
  end

  subscribe("user_contribution_history.modified") do |payload|
    message = {
      user: serializer.user(payload[:user]),
    }

    publish(message, schema: "github.users.v1.ContributionHistoryModified")
  end
end
