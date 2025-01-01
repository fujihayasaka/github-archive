# typed: true
# frozen_string_literal: true

class Marketplace::PendingInstallations::Notice
  def initialize(user_id:)
    @user_id = user_id
  end

  def dismiss
    return if dismissed?
    GitHub.kv.set(notice_key, Time.current.iso8601) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def dismissed?
    dismissed_at.present?
  end

  def dismissed_at
    time_string = notice_value
    return unless time_string.present?

    Time.zone.parse(time_string)
  end

  def reset
    GitHub.kv.del(notice_key) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  private

  def notice_value
    ActiveRecord::Base.connected_to(role: :reading) do
      GitHub.kv.get(notice_key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end

  def notice_key
    "user.marketplace.pending_installations.notice_dismissed_at.#{@user_id}"
  end
end
