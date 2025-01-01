# typed: true
# frozen_string_literal: true

class User
  class ProfileSettings
    PRIVATE_CONTRIBS_SETTING = "show_private_contribution_count"
    ACTIVITY_OVERVIEW_SETTING = "activity_overview"
    DISABLE_PRO_BADGE_SETTING = "disable_pro_badge"
    DISABLE_ACV_BADGE_SETTING = "disable_acv_badge"
    DISABLE_ACHIEVEMENTS_SETTING = "disable_achievements"
    OPT_OUT_PRIVATE_REPO_ACHIEVEMENT_TRACKING = "opt_out_private_repo_achievement_tracking"
    EMOJI_SKIN_TONE_PREFERENCE = :emoji_skin_tone_preference

    # enums for instrumenting beta features enrollment
    ACTIVITY_OVERVIEW_FEATURE = :org_scoped_activity
    PRO_BADGE_FEATURE = :pro_badge
    ACV_BADGE_FEATURE = :acv_badge
    NASA_BADGE_FEATURE = :nasa_badge

    def initialize(user)
      @user = user
    end

    # Public: Does this user want their contributions to private repositories to be shown in the
    # contributions graph and also summarized in the activity list on their profile?
    #
    # Returns a Boolean.
    def show_private_contribution_count?
      user_setting_enabled?(PRIVATE_CONTRIBS_SETTING)
    end
    alias_method :show_private_contribution_count, :show_private_contribution_count?

    def async_show_private_contribution_count?
      async_user_setting_enabled?(PRIVATE_CONTRIBS_SETTING)
    end

    # Public: Update the user's preference on whether private contribution counts should be shown
    # in their contributions graph and summarized in their profile activity list.
    #
    # value - Boolean, "1", or "0"
    #
    # Returns nothing.
    def show_private_contribution_count=(value)
      if update_user_setting(PRIVATE_CONTRIBS_SETTING, value)
        Contribution.clear_caches_for_user(@user)
        @user.instrument_private_contributions(enabled: value)
      end
    end

    # Public: Determines whether this user wants to show an 'Activity overview' section on their
    # profile, with links to filter contributions by organization.
    #
    # Returns a Boolean.
    def activity_overview_enabled?
      user_setting_enabled?(ACTIVITY_OVERVIEW_SETTING)
    end

    # Public: Update the user's preference on whether the "Activity overview" section should be
    # shown on their profile.
    #
    # value - Boolean, "1", or "0"
    #
    # Returns nothing.
    def activity_overview_enabled=(value)
      if update_user_setting(ACTIVITY_OVERVIEW_SETTING, value)
        if user_setting_enabled?(ACTIVITY_OVERVIEW_SETTING)
          GlobalInstrumenter.instrument("user.beta_feature.enroll",
            actor: @user,
            action: "enroll",
            feature: ACTIVITY_OVERVIEW_FEATURE,
          )
        else
          GlobalInstrumenter.instrument("user.beta_feature.unenroll",
            actor: @user,
            action: "unenroll",
            feature: ACTIVITY_OVERVIEW_FEATURE,
          )
        end
      end
    end

    # Public: Update the user's preference on whether the PRO badge should be
    # shown on their profile/hovercard (only if they have the Pro plan).
    #
    # value - Boolean, "1", or "0"
    #
    # Returns nothing.
    def pro_badge_enabled=(enable)
      # user setting is actually disabling the pro badge, but, for readability, all other
      # methods are referencing enabling the feature so the value needs to be flipped
      disable = toggle_setting_value(enable)

      if update_user_setting(DISABLE_PRO_BADGE_SETTING, disable)
        if user_setting_enabled?(DISABLE_PRO_BADGE_SETTING)
          GlobalInstrumenter.instrument("user.beta_feature.unenroll",
            actor: @user,
            action: "unenroll",
            feature: PRO_BADGE_FEATURE,
          )
        else
          GlobalInstrumenter.instrument("user.beta_feature.enroll",
            actor: @user,
            action: "enroll",
            feature: PRO_BADGE_FEATURE,
          )
        end
      end
    end

    # Public: Determines whether this user wants to enable the PRO badge on their profile/hovercard
    #
    # Returns a Boolean.
    def pro_badge_enabled?
      !user_setting_enabled?(DISABLE_PRO_BADGE_SETTING)
    end

    # Public: Update the user's preference on displaying the arctic code vault
    # contributor badge.
    #
    # enable - Boolean, "1", or "0"
    #
    # Returns nothing.
    def acv_badge_enabled=(enable)
      # Note: this setting is by default true, and we want to record the
      # opt-out, so we need to flip the value here.
      disable = toggle_setting_value(enable)
      update_user_setting(DISABLE_ACV_BADGE_SETTING, disable)
      if user_setting_enabled?(DISABLE_ACV_BADGE_SETTING)
        GlobalInstrumenter.instrument("user.beta_feature.unenroll",
          actor: @user,
          action: "unenroll",
          feature: ACV_BADGE_FEATURE,
        )
      else
        GlobalInstrumenter.instrument("user.beta_feature.enroll",
          actor: @user,
          action: "enroll",
          feature: ACV_BADGE_FEATURE,
        )
      end

      # double write to set achievements_enabled temporarily
      update_user_setting(DISABLE_ACHIEVEMENTS_SETTING, disable)
    end

    # Public: Determines whether this user has opted out of displaying the arctic
    # code vault contributor badge.
    #
    # Returns a Boolean.
    def acv_badge_enabled?
      !user_setting_enabled?(DISABLE_ACV_BADGE_SETTING)
    end

    # Public: Update the user's preference on displaying achievements.
    #
    # enable - Boolean, "1", or "0"
    #
    # Returns nothing.
    def achievements_enabled=(enable)
      # Note: this setting is by default true, and we want to record the
      # opt-out, so we need to flip the value here.
      disable = toggle_setting_value(enable)
      update_user_setting(DISABLE_ACHIEVEMENTS_SETTING, disable)

      # double write to disable other settings temporarily
      update_user_setting(DISABLE_ACV_BADGE_SETTING, disable)

      if badge = @user.profile_highlights.find_by_highlight_type("nasa_2020")
        badge.update!(hidden: disable)
      end
    end

    # Public: Determines whether this user has opted out of displaying
    # achievements.
    #
    # Returns a Boolean.
    def achievements_enabled?
      !user_setting_enabled?(DISABLE_ACHIEVEMENTS_SETTING)
    end

    # Public: Update the user's preference on opting-out of having their
    # private repositories be part of the achievements tracking.
    #
    # opt_out - Boolean, "1", or "0"
    #
    # Returns nothing.
    def all_private_projects_opted_out_of_achievements_tracking=(opt_out)
      update_user_setting(OPT_OUT_PRIVATE_REPO_ACHIEVEMENT_TRACKING, opt_out)
    end

    # Public: Determines whether this user has opted out of their private repos
    # being tracking for achievements.
    #
    # Returns a Boolean.
    def all_private_projects_opted_out_of_achievements_tracking?
      user_setting_enabled?(OPT_OUT_PRIVATE_REPO_ACHIEVEMENT_TRACKING)
    end

    def async_all_private_projects_opted_out_of_achievements_tracking?
      async_user_setting_enabled?(OPT_OUT_PRIVATE_REPO_ACHIEVEMENT_TRACKING)
    end

    def async_achievements_enabled?
      async_user_setting_enabled?(DISABLE_ACHIEVEMENTS_SETTING).then { |value| !value }
    end

    # Public: Update the user's preference on displaying the Mars 2020 Helicopter
    # Contributor badge.
    #
    # enable - Boolean, "1", or "0"
    #
    # Returns nothing.
    def nasa_badge_enabled=(enable)
      badge = @user.profile_highlights.find_by_highlight_type("nasa_2020")
      return unless badge

      value = toggle_setting_value(enable)
      badge.update!(hidden: value)
      if badge.hidden?
        GlobalInstrumenter.instrument("user.beta_feature.unenroll",
          actor: @user,
          action: "unenroll",
          feature: NASA_BADGE_FEATURE,
        )
      else
        GlobalInstrumenter.instrument("user.beta_feature.enroll",
          actor: @user,
          action: "enroll",
          feature: NASA_BADGE_FEATURE,
        )
      end

      # double write to set achievements_enabled temporarily
      update_user_setting(DISABLE_ACHIEVEMENTS_SETTING, value)
    end

    # Public: Determines whether this user has opted out of isplaying the
    # Mars 2020 Helicopter Contributor badge.
    #
    # Returns a Boolean.
    def nasa_badge_enabled?
      badge = @user.profile_highlights.find_by_highlight_type("nasa_2020")
      return false unless badge

      !badge.hidden?
    end

    # Public: Returns user's preferred emoji skin tone index.

    # Returns the preferred skin tone for emoji that support it. The
    # default tone is zero.
    #
    # https://en.wikipedia.org/wiki/Fitzpatrick_scale
    #
    # Returns a Integer 0-5.
    def preferred_emoji_skin_tone
      default_value = 0
      return default_value if @user.new_record?

      if defined? @preferred_emoji_skin_tone
        return @preferred_emoji_skin_tone
      end

      result = Profiles::Kv.store.get("user.#{EMOJI_SKIN_TONE_PREFERENCE}.#{@user.id}")
      value = result.value { default_value }.to_i # On errors, the block value is returned
      @preferred_emoji_skin_tone = value if result.ok?

      value
    end

    # Public: Update user's emoji skin tone preference.
    #
    # value - Number between 0-5
    #
    # Returns nothing.
    def set_preferred_emoji_skin_tone=(value)
      return unless @user.persisted?
      value = [0, 1, 2, 3, 4, 5].include?(value.to_i) ? value.to_i : 0

      @preferred_emoji_skin_tone = value
      Profiles::Kv.store.set("user.#{EMOJI_SKIN_TONE_PREFERENCE}.#{@user.id}", value.to_s)
    end

    private

    def toggle_setting_value(value)
      case value
      when "0" then "1"
      when "1" then "0"
      when true then false
      when false then true
      end
    end

    def user_setting_enabled?(setting)
      return false if @user.new_record?

      result = Profiles::Kv.store.get("user.#{setting}.#{@user.id}")
      value = result.value { "false" } # On errors, the block value is returned
      value == "true"
    end

    def async_user_setting_enabled?(setting)
      return Promise.resolve(false) if @user.new_record?

      Platform::Loaders::ProfilesKv.load("user.#{setting}.#{@user.id}").then { |value| value == "true" }
    end

    # Private: Enable or disable a user profile setting for this user.
    #
    # setting - String or Symbol; the setting to change
    # value - Boolean; whether or not to enable the setting
    #
    # Returns true if setting was changed, false otherwise.
    def update_user_setting(setting, value)
      return false unless @user.persisted?

      value = false if %w(0 false).include?(value)
      value = !!value
      Profiles::Kv.store.set("user.#{setting}.#{@user.id}", value.to_s)
      true
    end
  end
end
