# typed: true
# frozen_string_literal: true

module User::MobileDependency
  extend T::Helpers
  requires_ancestor { User }

  def uses_mobile_app?
    GitHub.dogstats.distribution_time("user.uses_mobile_app") do
      oauth_accesses.where(application_id: mobile_app_ids).any?
    end
  end

  def has_mobile_app_activity?(since)
    GitHub.dogstats.distribution_time("user.has_mobile_app_activity") do
      oauth_accesses.where("application_id IN (?) AND accessed_at > ?", mobile_app_ids, since).any?
    end
  end

  private

  def mobile_app_ids
    @mobile_app_ids ||= Apps::Internal.oauth_application_ids([:ios_mobile, :android_mobile]).values.compact
  end
end
