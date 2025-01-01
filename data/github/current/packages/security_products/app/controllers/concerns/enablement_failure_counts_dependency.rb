# typed: true
# frozen_string_literal: true

module EnablementFailureCountsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Orgs::Controller }

  ENABLEMENT_FAILURES_JSON_PATH = Rails.root.join("config", "code_security_configuration_failures.json")
  ENABLEMENT_FAILURES_MAP = begin
    T.let(
      JSON.parse(File.read(ENABLEMENT_FAILURES_JSON_PATH))["failures"],
      T::Hash[String, T.untyped]
    )
  rescue JSON::ParserError, Errno::ENOENT => e
    Failbot.report(e)
    {}
  end

  sig { returns(T.nilable(T::Hash[String, Integer])) }
  def failure_counts
    # Failsafe if ENABLEMENT_FAILURES_MAP isn't loaded:
    return {} if ENABLEMENT_FAILURES_MAP.blank?
    return {} if banner_dismissed_for_user_in_org?

    full_counts = ActiveRecord::Base.connected_to(role: :reading) do
      RepositorySecurityConfiguration.where(
        organization_id: current_organization.id,
        state: :failed
      ).group(:failure_reason).count
    end

    # If we have nil failure_reasons, replace them with the text "Unknown":
    if full_counts[nil].present?
      full_counts["Unknown"] = full_counts.delete(nil)
    end

    # To ensure we consolodate all the counts correctly, reference the front-end failure reason and combine as needed:
    counts = full_counts.reduce({}) do |memo, (reason, count)|
      banner_reason = ENABLEMENT_FAILURES_MAP.dig(reason, "frontend_banner_reason") \
        || ENABLEMENT_FAILURES_MAP.dig("Unknown", "frontend_banner_reason")

      memo[banner_reason] ||= 0
      memo[banner_reason] += count
      memo
    end

    counts
  end

  sig { returns(String) }
  def user_dismissed_banner_for_org_key
    ActiveRecord::Base.connected_to(role: :reading) do
      ["failure_banner_dismissed_for", current_user.id, current_organization.id].join(":")
    end
  end

  sig { returns(T.nilable(String)) }
  def latest_failure_timestamp
    ActiveRecord::Base.connected_to(role: :reading) do
      RepositorySecurityConfiguration \
        .where(organization_id: current_organization.id, state: :failed)
        .pluck(:updated_at)
        &.last&.to_i&.to_s
    end
  end

  sig { returns(T::Boolean) }
  def banner_dismissed_for_user_in_org?
    dismissed_at = ActiveRecord::Base.connected_to(role: :reading) do
      SecurityProductsEnablement::KV.get(user_dismissed_banner_for_org_key).value!
    end
    return false if dismissed_at.nil?

    dismissed_at == latest_failure_timestamp
  end
end
