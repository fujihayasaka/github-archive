# typed: true
# frozen_string_literal: true

# Used for storing user contributions that occured on an external enterprise instance or within a GHEC business
# account.
class EnterpriseContribution < ApplicationRecord::Collab
  DELETE_BATCH_SIZE = 50
  CLEAR_CACHE_BATCH_SIZE = 50
  BACKFILL_INTERVAL = 3.months

  scope :enterprise_installation, lambda { |id| where(enterprise_installation_id: id) }
  scope :business, lambda { |id| where(business_id: id) }
  scope :for_date, lambda { |date| where(contributed_on: date) }

  belongs_to :user, required: true
  # Can belong to either a Connected GHES instance, or a GHEC account (Business)
  belongs_to :enterprise_installation
  belongs_to :business

  validates :count, presence: true
  validates :contributed_on, presence: true

  # This method is only used on a GHES instance
  def self.push_user_contributions_history(user)
    return unless GitHub.dotcom_user_connection_enabled?

    Failbot.push(github_connect_push_contributions_history: true)

    contributions = index_contributions_by_date(user)
    user_token = DotcomUser.for(user).token

    GitHub::Connect.post_contribution_data(user_token, user.login, contributions)
    DotcomUser.update_user_last_contributions_sync(user)
  end

  # This method is only used on a GHES instance
  def self.push_new_contributions
    return unless GitHub.dotcom_user_connection_enabled?

    GitHubConnectPushNewContributionsJob.perform_later
  end

  # Save enterprise contributions to the database
  # The contributions are grouped per EnterpriseInstallation/Business and also date created
  #
  # Returns nothing.
  def self.insert_or_update_contribution(user, installation_or_business, contributed_on, count)
    scope =
      case installation_or_business
      when EnterpriseInstallation
        user.enterprise_contributions.enterprise_installation(installation_or_business.id)
      when Business
        user.enterprise_contributions.business(installation_or_business.id)
      end
    if contrib = scope.where(contributed_on: contributed_on).first
      if count <= 0
        contrib.destroy
        return nil
      elsif contrib.count != count
        contrib.update_attribute(:count, count)
      end
      contrib
    elsif count > 0
      scope.create(contributed_on: contributed_on, count: count)
    end
  end

  # Queue up a GitHubConnectDestroyInstallationContributions job.
  #
  # installation - the installation which contributions will be deleted
  #
  # Returns nothing.
  def self.clear_installation_contributions(installation)
    GitHubConnectDestroyInstallationContributionsJob.perform_later(installation.id)
  end

  # Clear enterprise installation contributions
  #
  # installation_id - the id for the (potentially already deleted) installation
  #                   of which contributions will be deleted
  #
  # Returns nothing.
  def self.clear_installation_contributions!(installation_id)
    contribution_ids = enterprise_installation(installation_id).pluck(:id)
    user_ids = enterprise_installation(installation_id).select(:user_id).distinct.pluck(:user_id)
    contribution_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      EnterpriseContribution.throttle do
        EnterpriseContribution.where(id: slice).delete_all
      end
    end
    user_ids.each_slice(CLEAR_CACHE_BATCH_SIZE) do |slice|
      ApplicationRecord::Domain::KeyValues.throttle do
        User.where(id: slice).each do |user|
          Contribution.clear_caches_for_user(user)
        end
      end
    end
  end

  # Queue up a GitHubConnectDestroyInstallationContributions job.
  #
  # user - the user whose contributions will be deleted
  # installation - the installation for which user contributions will be deleted
  #
  # Returns nothing.
  def self.clear_user_contributions(user, installation)
    GitHubConnectDestroyUserContributionsJob.perform_later(user, installation.id)
  end

  # Clear user contributions that are specific to that installation
  #
  # user - the user whose contributions will be deleted
  # installation_id - the id for the relevant installation. We receive an id
  #                   because this may be asynchronously clearing contributionsan
  #                   for an already deleted installation.
  #
  # Returns nothing.
  def self.clear_user_contributions!(user, installation_id)
    contribution_ids = user.enterprise_contributions.enterprise_installation(installation_id).ids
    contribution_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      throttle do
        EnterpriseContribution.where(id: slice).delete_all
      end
    end
    Contribution.clear_caches_for_user(user)
  end

  # Takes a user and gets the user's contributions within the last 3 months
  # It the indexes them by date with a contribution count for that date:
  #
  # [{"date" => 2018-04-24T00:00:00Z, "count" => 3}, {"date" => 2018-04-25T00:00:00Z, "count" => 7}, ..]
  #
  # Returns an Array of Hashes.
  def self.index_contributions_by_date(user)
    contributions_collector = Contribution::Collector.new(user: user, time_range: (Time.zone.now - BACKFILL_INTERVAL)..(Time.zone.now))
    contributions_collector.contribution_count_by_day.map do |date, count|
      { "date" => date.to_time.utc.iso8601, "count" => count }
    end
  end
end
