# typed: true
# frozen_string_literal: true

class EmuContributionSharingSyncJob < ApplicationJob
  queue_as :emu_contribution_sharing
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  def perform
    # Batch loop (count is 1000 by default) through every user who has a 'shares_contributions_with' setting set
    UserSettings.where.not(shares_contributions_with: nil).find_each do |sharing_emu_settings|
      emu = User.find(sharing_emu_settings.user_id)
      personal_user = User.find(T.must(sharing_emu_settings.shares_contributions_with))
      emu_contribs = index_contributions_by_date(
        emu,
        find_last_contribution_sync(personal_user, emu.enterprise_managed_business) || Time.zone.now)
      emu_contribs.each do |contrib|
        count = contrib["count"]
        date = contrib["date"]
        with_write do
          EnterpriseContribution.insert_or_update_contribution \
            personal_user, emu.enterprise_managed_business, date, count
        end
      end
    end
  end

  private

  def index_contributions_by_date(user, last_contributions_sync)
    yesterday = (last_contributions_sync.to_date - 1).to_time
    # Instantiate a Collector with the viewer as the user, so we get a count of everything - not just
    # what others see
    contributions_collector = Contribution::Collector.new(
      user: user, viewer: user, time_range: (yesterday)..(Time.zone.now))

    contributions_collector.contribution_count_by_day.map do |date, count|
      { "date" => date.to_time.utc.iso8601, "count" => count }
    end
  end

  def find_last_contribution_sync(user, business)
    # Find the last sync date for this user by looking at the last EnterpriseContribution updated_at timestamp for the
    # user and associated EMU business
    last_contribution_sync = EnterpriseContribution.where(user: user, business: business).order(updated_at: :desc).first
    last_contribution_sync.updated_at if last_contribution_sync
  end
end
