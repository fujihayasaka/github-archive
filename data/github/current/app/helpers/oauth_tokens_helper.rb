# typed: true
# frozen_string_literal: true

module OauthTokensHelper
  NO_EXPIRATION_NOTE = "The token will never expire!"
  DEFAULT_TIMEFRAMES = [7, 30, 60, 90]

  def format_expiry_note(days)
    "The token will expire on #{days.days.from_now.strftime("%a, %b %e %Y")}"
  end

  def display_expiration_date(token)
    human_expiration_date(token.expires_at)
  end

  def human_expiration_date(expiration_time)
    return "" if expiration_time.nil?

    local_expiration_time = expiration_time.in_time_zone(Time.zone)
    if local_expiration_time.today?
      "today"
    elsif local_expiration_time.yesterday?
      "yesterday"
    else
      "on #{local_expiration_time.strftime("%a, %b %e %Y")}"
    end
  end

  def custom_expiration_timeframe?(timeframe, extra_timeframes: [])
    return false unless timeframe.present?

    (DEFAULT_TIMEFRAMES + extra_timeframes).exclude?(timeframe.to_i)
  end

  def expiration_timeframes(allow_none: true, exempts_actor: false, target_expiration_limit: nil, target_and_type_with_expiration: nil, extra_timeframes: [])
    target_expiration_limit = nil if exempts_actor
    time_frames = (DEFAULT_TIMEFRAMES + extra_timeframes).uniq.sort.map do |days|
      ["#{days} days", days.to_s, { "data-human-date" => format_expiry_note(days) }]
    end

    if target_expiration_limit
      allow_none = false
      time_frames.reject! { |_, days, _| days.to_i > target_expiration_limit }

      # check if the limit is already in the list
      time_frame_index = time_frames.find_index { |_, days, _| days.to_i == target_expiration_limit }

      if time_frame_index
        # If the limit is already in the list, update the description
        T.must(time_frames[time_frame_index])[2].merge!({
          "data-target" => target_and_type_with_expiration
        })
      else
        # If the limit is different from the default, add it to the list
        time_frames << ["#{target_expiration_limit} days", target_expiration_limit.to_s, {
          "data-custom-limit" => "true",
          "data-human-date" => format_expiry_note(target_expiration_limit),
          "data-target" => target_and_type_with_expiration
          }] unless time_frames.map { |_, days, _| days.to_i }.include?(target_expiration_limit)
      end
    end

    time_frames << ["Custom...", "custom", { "data-human-date" => nil, "data-description" => target_expiration_limit ? "between 1 and #{target_expiration_limit} days" : nil }]
    return time_frames unless allow_none

    time_frames << ["No expiration", "none", { "data-human-date" => NO_EXPIRATION_NOTE }]
  end

  def expiration_timeframe_default_selected_value(access:, target_expiration_limit: nil)
    return access.default_expires_at if !target_expiration_limit || access.default_expires_at == "custom"

    target_expiration_limit.to_i > 30 ? "30" : target_expiration_limit.to_s
  end

  def fine_grained_lifetime_limit_for(target)
    target = expiration_limit_enforcer(target)

    return nil if target.blank? || target.user?
    return nil unless target.personal_access_token_expiration_limit_enabled?

    ProgrammaticAccessTokenLifetimeConfiguration.new(target, ProgrammaticAccessTokenType::FineGrained).expiration_limit
  end

  def fine_grained_lifetime_limit_exempted_for?(target, actor)
    actor_exempted_from_lifetime_limit?(target, actor, ProgrammaticAccessTokenType::FineGrained)
  end

  def classic_lifetime_limit_exempted_for_enterprise_user?(actor)
    return unless actor.feature_enabled?(:classic_pat_expiration_lifecycle_enforcement)
    return unless business = pat_lifetime_policy_enterprise_for(actor)
    return unless business.personal_access_token_expiration_limit_enabled?

    actor_exempted_from_lifetime_limit?(business, actor, ProgrammaticAccessTokenType::Classic)
  end

  def actor_exempted_from_lifetime_limit?(target, actor, pat_type)
    return true if target.blank? || target.user?
    return true unless target.personal_access_token_expiration_limit_enabled?

    ProgrammaticAccessTokenLifetimeConfiguration.new(target, pat_type).exempted_for?(actor)
  end

  def classic_lifetime_limit_for_enterprise(actor)
    return unless actor.feature_enabled?(:classic_pat_expiration_lifecycle_enforcement)
    return unless business = pat_lifetime_policy_enterprise_for(actor)
    return unless business.personal_access_token_expiration_limit_enabled?

    ProgrammaticAccessTokenLifetimeConfiguration.new(business, ProgrammaticAccessTokenType::Classic).expiration_limit
  end

  def target_and_type_with_expiration_for_enterprise(user)
    return unless business = pat_lifetime_policy_enterprise_for(user)

    ProgrammaticAccessTokenLifetimeConfiguration
      .new(business, ProgrammaticAccessTokenType::Classic)
      .target_and_type_with_limit
  end

  def pat_lifetime_policy_enterprise_for(actor)
    GitHub.enterprise? ? GitHub.global_business : actor.enterprise_managed_business
  end

  def fine_grained_target_and_type_with_limit(target)
    target = expiration_limit_enforcer(target)

    return nil unless target
    return nil if target.user?

    ProgrammaticAccessTokenLifetimeConfiguration.new(target, ProgrammaticAccessTokenType::FineGrained).target_and_type_with_limit
  end

  # Remove this method in favor of new_date_picker_expiration_helper_note when the fg_pat_expiration_lifecycle_enforcement feature flag is removed
  def expiration_helper_note(access_token)
    if access_token.default_expires_at == "custom"
      ""
    elsif access_token.default_expires_at == "none"
      NO_EXPIRATION_NOTE
    else
      format_expiry_note(access_token.default_expires_at.to_i)
    end
  end

  def new_date_picker_expiration_helper_note(value)
    if value == "custom"
      ""
    elsif value == "none"
      NO_EXPIRATION_NOTE
    else
      format_expiry_note(value.to_i)
    end
  end

  def expiration_limit_enforcer(target)
    # When the target is a user in EMU mode or GHES, we need to check the business to get the expiration limit
    return unless target
    return target unless target.user?
    return target unless business = pat_lifetime_policy_enterprise_for(target)

    business
  end
end
