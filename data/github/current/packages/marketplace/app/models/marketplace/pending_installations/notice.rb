# typed: true
# frozen_string_literal: true

require_relative "../k_v"

class Marketplace::PendingInstallations::Notice
  def initialize(user_id:)
    @user_id = user_id
  end

  def dismiss
    return if dismissed?
    Marketplace::KV.store.set(notice_key, Time.current.iso8601)
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
    Marketplace::KV.store.del(notice_key)
  end

  private

  def notice_value
    ActiveRecord::Base.connected_to(role: :reading) do
      Marketplace::KV.store.get(notice_key).value!
    end
  end

  def notice_key
    "user.marketplace.pending_installations.notice_dismissed_at.#{@user_id}"
  end
end
