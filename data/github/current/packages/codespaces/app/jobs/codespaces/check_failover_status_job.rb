# typed: true
# frozen_string_literal: true

class Codespaces::CheckFailoverStatusJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  schedule interval: 30.minutes, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit

  def perform
    failed_over_messages = []

    Codespaces::VscsServiceStamp.where(vscs_target: :production).each do |stamp|
      creates_pct = stamp.percent_available_for_creates
      resumes_pct = stamp.percent_available_for_resumes
      if creates_pct < 100 || resumes_pct < 100
        failed_over_messages << "#{stamp.region}: (creates: #{creates_pct}% allowed, resumes: #{resumes_pct}% allowed)"
      end
    end

    unless failed_over_messages.empty?
      GitHub::Chatterbox.client.say!(
        "#codespaces-ops",
        ":fluent-globe_with_meridians::yellow_alert: #{failed_over_messages.count} regions are currently failed over in production:\n* #{failed_over_messages.join("\n* ")}",
      )
    end
  end
end
