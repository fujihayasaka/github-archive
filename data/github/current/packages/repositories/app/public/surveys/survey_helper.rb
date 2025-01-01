# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Surveys
  class SurveyHelper

    def initialize(slug:, cooldown_days: 90, user_rate_percent: 30)
      @slug = slug
      @cooldown_days = cooldown_days
      @user_rate_percent = user_rate_percent
    end

    #  Returns a value indicating whether the survey prompt should be shown for the given user
    def show_survey_prompt_for_user?(user)
      return false if GitHub.enterprise?
      user_in_current_survey?(user) && !survey_hidden_for_user?(user)
    end

    #  Hide the survey for the given user for @cooldown_days and record it as dismissed
    def dismiss_survey(user)
      hide_survey_for_user(user)
      emit_stat("dismissed")
    end

    #  Hide the survey for the given user for @cooldown_days and record it as answered
    def answered_survey(user)
      # Mark the survey as hidden so we don't have to query for answers in order to not show
      # the prompt again.
      hide_survey_for_user(user)
      emit_stat("answered")
    end

    def survey_hidden_for_user?(user)
      Repositories::Kv.store.exists(key_for_user(user)).value { false }
    end

    def user_in_current_survey?(user)
      # Include up to @user_rate_percent of all users per month
      current_month = Time.now.utc.to_date.month

      # Generate a checksum based on the user id, slug, and month. This is used to create variation in users who see the survey every month.
      Zlib.crc32(user.id.to_s + @slug + current_month.to_s) % 100 < @user_rate_percent
    end

    private

    def hide_survey_for_user(user)
      Repositories::Kv.store.set(key_for_user(user), "true", expires: @cooldown_days.days.from_now)
    end

    # Emit a counter in the context for the survey including the given action as tag
    def emit_stat(action)
      GitHub.dogstats.increment("surveys.#{@slug}", tags: ["action:#{action}"])
    end

    def key_for_user(user)
      "user.#{@slug}-hidden.#{user.id}"
    end
  end
end
