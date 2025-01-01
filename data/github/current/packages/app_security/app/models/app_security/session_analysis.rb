# typed: strict
# frozen_string_literal: true

module AppSecurity
  class SessionAnalysis

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    attr_reader :data

    IP = "ip"
    UA = "user_agent"
    TIMEZONE = "time_zone_name"
    ANDROID_LINUX = T.let(["Android", "Generic Linux"], T::Array[String])
    CHROME_EDGE = T.let(["Chrome", "Microsoft Edge"], T::Array[String])
    SAFARI_UNKNOWN = T.let(["Unknown Browser", "Safari"], T::Array[String])
    APPLE = T.let(["macOS", "iOS (iPad)", "iOS (iPhone)"], T::Array[String])

    sig { params(session: UserSession, updated_attributes: T::Array[String]).void }
    def initialize(session, updated_attributes)
      @session = session
      @updated_attributes = updated_attributes
      @browser_before = T.let(Browser.new(@session.user_agent_before_last_save), T.untyped)
      @browser_after = T.let(Browser.new(@session.user_agent), T.untyped)
      @should_instrument = T.let(false, T.nilable(T::Boolean))

      run
    end

    sig { returns(T.nilable(T::Boolean)) }
    def should_instrument?
      @should_instrument
    end

    sig { returns(T.nilable(T::Boolean)) }
    def strong_revoke_outcome?
      @data && @data[:ip_change] && [:high].include?(@data[:user_agent_change_risk]) && [:browser].include?(@data[:user_agent_mismatch])
    end

    sig { returns(T.nilable(T::Boolean)) }
    def revoke_outcome?
      return false unless @data
      return true if [:high].include?(@data[:user_agent_change_risk]) && [:browser].include?(@data[:user_agent_mismatch])

      @data[:country_change] && [:medium].include?(@data[:user_agent_change_risk]) && [:browser_version].include?(@data[:user_agent_mismatch])
    end

    sig { returns(T.nilable(T::Boolean)) }
    def should_revoke?
      return unless @session.user&.feature_enabled?(:session_analysis_revoke)
      return true if @session.user&.feature_enabled?(:session_analysis_expand_revoke) && revoke_outcome?

      strong_revoke_outcome?
    end

    private

    sig { void }
    def run
      location_before = GitHub::Location.look_up(@session.ip_before_last_save)
      location_after = GitHub::Location.look_up(@session.ip)

      ip_change = IP.in?(@updated_attributes)
      user_agent_change = UA.in?(@updated_attributes)
      timezone_change = TIMEZONE.in?(@updated_attributes)
      country_change = ip_change && location_before[:country_code] != location_after[:country_code]
      @should_instrument = T.let(country_change || user_agent_change || timezone_change, T.nilable(T::Boolean))
      return unless ip_change || user_agent_change || timezone_change

      risk, mismatch, message = analyze_user_agent
      should_log = country_change || (mismatch != :mismatch_none)

      GitHub.logger.info(
        {
          "code.function" => "user_session.risk_analysis",
          "gh.enduser.id" => @session.user_id,
          "gh.auth.session.id" => @session.id,
          "gh.auth.accessed_at_was" => @session.accessed_at_before_last_save,
          "gh.auth.ip" => @session.ip,
          "gh.auth.ip_was" => @session.ip_before_last_save,
          "gh.auth.timezone" => @session.time_zone_name,
          "gh.auth.timezone_was" => @session.time_zone_name_before_last_save,
          "gh.auth.location" => location_after,
          "gh.auth.location_was" => location_before,
          "user_agent.original_was" => @browser_before.ua,
          "user_agent.original" => @browser_after.ua,
          "gh.auth.session_update.mismatch" => mismatch,
          "gh.auth.session_update.risk" => risk,
          "gh.auth.session_update.message" => message,
          "gh.auth.session_update.ip_change" => ip_change,
          "gh.auth.session_update.zone_change" => timezone_change,
          "gh.auth.session_update.country_change" => country_change,
        }
      ) if should_log

      GitHub.dogstats.increment("user_session.change_analysis", tags: [
        "ip_change:#{ip_change}",
        "timezone_change:#{timezone_change}",
        "country_change:#{country_change}",
        "user_agent_change:#{user_agent_change}",
        "user_agent_change_risk:#{risk}",
        "user_agent_change_mismatch:#{mismatch}",
      ])

      @data = T.let({
        ip_change: ip_change,
        timezone_change: timezone_change,
        country_change: country_change,
        user_agent_change: user_agent_change,
        user_agent_mismatch: mismatch,
        user_agent_change_risk: risk,
        user_agent_change_message: message
      }, T.nilable(T::Hash[T.untyped, T.untyped]))
    end

    sig { returns([Symbol, Symbol, String]) }
    def analyze_user_agent
      result = default_result

      if browser_mismatch
        # both scenarios are common and not correlated with abuse
        if chrome_to_edge || safari_to_unknown
          result = browser_mismatch_result(:low)
        else
          return browser_mismatch_result(:high)
        end
      end

      # don't compare browser versions for the safari unknown scenario which won't match and needs to be ignored
      if browser_version_mismatch && !safari_to_unknown
        if browser_version_upgrade
          result = browser_version_acceptable_mismatch_result(:risk_none)
        else
          return safe_browser_version_downgrade ? browser_version_acceptable_mismatch_result(:low) : browser_version_mismatch_result
        end
      end

      if platform_mismatch
        # some Android UAs are marked as Linux
        if android_to_linux
          result = platform_mismatch_result(:low)
        # MacOs to iOS, etc
        elsif apple_family
          result = platform_mismatch_result(:low)
        else
          return platform_mismatch_result(:medium)
        end
      elsif device_mismatch
        return device_mismatch_result
      elsif platform_version_mismatch
        return platform_version_mismatch_result
      end

      result
    end

    sig { returns(T::Boolean) }
    def device_mismatch
      @browser_before.device.name != @browser_after.device.name
    end

    sig { returns([Symbol, Symbol, String]) }
    def device_mismatch_result
      [:medium, :device, "Device type changed (#{@browser_before.device.name} to #{@browser_after.device.name})"]
    end

    sig { returns(T::Boolean) }
    def platform_mismatch
      @browser_before.platform.name != @browser_after.platform.name
    end

    sig { params(risk: Symbol).returns([Symbol, Symbol, String]) }
    def platform_mismatch_result(risk)
      [risk, :platform, "Platform changed (#{platform_diff_string})"]
    end

    sig { returns(T::Boolean) }
    def android_to_linux
      @browser_before.platform.name.in?(ANDROID_LINUX) && @browser_after.platform.name.in?(ANDROID_LINUX)
    end

    sig { returns(T::Boolean) }
    def apple_family
      @browser_before.platform.name.in?(APPLE) && @browser_after.platform.name.in?(APPLE)
    end

    sig { returns(T::Boolean) }
    def platform_version_mismatch
      @browser_before.platform.version.to_i > @browser_after.platform.version.to_i
    end

    sig { returns([Symbol, Symbol, String]) }
    def platform_version_mismatch_result
      [:medium, :platform_version, "Platform version changed (#{platform_diff_string})"]
    end

    sig { returns(T::Boolean) }
    def browser_mismatch
      @browser_before.name != @browser_after.name
    end

    sig { returns(T::Boolean) }
    def chrome_to_edge
      @browser_before.name.in?(CHROME_EDGE) && @browser_after.name.in?(CHROME_EDGE)
    end

    sig { returns(T::Boolean) }
    def safari_to_unknown
      @browser_before.name.in?(SAFARI_UNKNOWN) && @browser_after.name.in?(SAFARI_UNKNOWN)
    end

    sig { params(risk: Symbol).returns([Symbol, Symbol, String]) }
    def browser_mismatch_result(risk)
      [risk, :browser, "Browser changed (#{browser_diff_string})"]
    end

    sig { returns(T::Boolean) }
    def browser_version_mismatch
      @browser_before.version.to_i != @browser_after.version.to_i
    end

    sig { returns(T::Boolean) }
    def browser_version_upgrade
      @browser_before.version.to_i < @browser_after.version.to_i
    end

    sig { returns(T::Boolean) }
    def safe_browser_version_downgrade
      @browser_before.version.to_i - 1 == @browser_after.version.to_i
    end

    sig { returns([Symbol, Symbol, String]) }
    def browser_version_mismatch_result
      [:medium, :browser_version, "Browser version changed (#{browser_diff_string})"]
    end

    sig { params(risk: Symbol).returns([Symbol, Symbol, String]) }
    def browser_version_acceptable_mismatch_result(risk)
      [risk, :browser_version, "Acceptable browser version change (#{browser_diff_string})"]
    end

    sig { returns([Symbol, Symbol, String]) }
    def default_result
      [:risk_none, :mismatch_none, "No risk detected: user agent consistent"]
    end

    sig { returns(String) }
    def browser_diff_string
      "#{@browser_before.name}:#{@browser_before.version} to #{@browser_after.name}:#{@browser_after.version}"
    end

    sig { returns(String) }
    def platform_diff_string
      "#{@browser_before.platform.name}:#{@browser_before.platform.version.to_i} to #{@browser_after.platform.name}:#{@browser_after.platform.version.to_i}"
    end
  end
end
