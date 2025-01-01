# typed: strict
# frozen_string_literal: true

module SecurityCampaigns

  # This class contains helper methods for accessing the functionality of a security campaign.
  # It also provides methods for loading campaigns alerts (`security_campaign_alerts`). Which
  # can be used by subclasses to provide more specific functionality.
  class CampaignBase

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign, open_count: Integer, closed_count: Integer, open_with_links_count: Integer).void }
    def initialize(security_campaign, open_count, closed_count, open_with_links_count)
      @security_campaign = security_campaign
      @open_count = open_count
      @closed_count = closed_count
      @open_with_links_count = open_with_links_count
      @open_without_links_count = T.let(@open_count - @open_with_links_count, Integer)
      @total_count = T.let(@open_count + @closed_count, Integer)
    end

    sig { returns(SecurityCampaigns::SecurityCampaign) }
    attr_reader :security_campaign

    sig { returns(Integer) }
    attr_reader :open_count

    sig { returns(Integer) }
    attr_reader :closed_count

    sig { returns(Integer) }
    attr_reader :total_count

    sig { returns(Integer) }
    attr_reader :open_with_links_count

    sig { returns(Integer) }
    attr_reader :open_without_links_count

    sig { returns(T.nilable(Integer)) }
    def id
      @security_campaign.id
    end

    sig { returns(Integer) }
    def number
      @security_campaign.number
    end

    sig { returns(String) }
    def name_for_display
      @security_campaign.name
    end

    sig { returns(Integer) }
    def days_left
      # We need to calculate the time similar to our React app to avoid discrepancy
      ((@security_campaign.ends_at - DateTime.current) / (60 * 60 * 24)).floor
    end

    sig { returns(Integer) }
    def closed_percentage
      return 0 if @total_count == 0

      @closed_count * 100 / @total_count
    end

    # load_campaign_alerts loads the alerts for the specified security campaigns
    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        repo: T.nilable(Repository),
        strategy: T.nilable(CodeScanning::AlertQueryService::ScopeStrategy),
        alert_numbers: T.nilable(T::Hash[Integer, T::Array[Integer]]),
      ).returns(T::Array[SecurityCampaignAlert])
    end
    def self.load_campaign_alerts(security_campaigns, repo:, strategy:, alert_numbers:)
      # Fetch alerts from db
      campaign_alerts = fetch_campaign_alerts(security_campaigns, repo, alert_numbers).to_a
      # If we are in an org-level context we need to filter away alerts that are in a
      # repository that is no longer part of the campaign org
      # This can happen if a repository is moved to another org, but the campaign alerts were not deleted
      filter_campaign_alerts(security_campaigns, campaign_alerts, strategy:)
    end

    # Convert campaign alerts into a sorted and deduplicated list of RepoNumber's
    sig { params(campaign_alerts: T::Array[SecurityCampaignAlert]).returns(T::Array[Turboscan::Proto::RepoNumber]) }
    def self.repo_numbers_from_alerts(campaign_alerts)
      campaign_alerts.map do |alert|
        Turboscan::Proto::RepoNumber.new(
          repository_id: alert.repository_id,
          number: alert.logical_alert_number,
        )
      end.uniq { |rn| [rn.repository_id, rn.number] }.sort_by { |rn| [rn.repository_id, rn.number] }
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        repo: T.nilable(Repository),
        alert_numbers: T.nilable(T::Hash[Integer, T::Array[Integer]]),
      ).returns(ActiveRecord::Relation)
    end
    private_class_method def self.fetch_campaign_alerts(security_campaigns, repo, alert_numbers)
      tags = ["kind:campaign_alerts"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        scope = if repo.nil?
          SecurityCampaignAlert.where(security_campaign_id: security_campaigns.map(&:id))
        else
          SecurityCampaignAlert.where(security_campaign_id: security_campaigns.map(&:id), repository_id: repo.id)
        end

        unless alert_numbers.nil?
          # If alert numbers are given, we'll only select alert numbers that are in the given list
          arel_table = SecurityCampaignAlert.arel_table
          conditions = alert_numbers.map do |repository_id, numbers|
            arel_table[:repository_id].eq(repository_id).and(arel_table[:logical_alert_number].in(numbers))
          end

          scope = scope.where(conditions.inject(&:or))
        end

        scope
      end
    end

    sig do
      params(org: T.nilable(Organization)).
      returns(ActiveRecord::Relation)
    end
    private_class_method def self.targetable_repositories(org)
      return Repository.none if org.nil?

      org.repositories.active
    end

    sig do
      params(
        strategy: CodeScanning::AlertQueryService::ScopeStrategy,
        scope: ActiveRecord::Relation,
      ).returns(ActiveRecord::Relation)
    end
    def self.filter_repositories(strategy:, scope:)
      filters = {}
      begin
        strategy.with_repository_ids!(filters)
      rescue CodeScanning::AlertQueryService::EmptyResultError
        return Repository.none
      end

      if filters[:repository_ids]
        scope = scope.merge(Repository.where(id: filters[:repository_ids]))
      end
      if filters[:excluded_repository_ids]
        scope = scope.merge(Repository.where.not(id: filters[:excluded_repository_ids]))
      end

      scope
    end

    sig do
      params(
        security_campaigns: T::Array[SecurityCampaigns::SecurityCampaign],
        campaign_alerts: T::Array[SecurityCampaignAlert],
        strategy: T.nilable(CodeScanning::AlertQueryService::ScopeStrategy),
      ).returns(T::Array[SecurityCampaignAlert])
    end
    def self.filter_campaign_alerts(security_campaigns, campaign_alerts, strategy:)
      tags = ["kind:filter_alerts"]
      GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: tags) do
        # Find all orgs that are part of the security campaigns
        # In current use this will only be a single one
        org_ids = security_campaigns.map(&:organization_id).uniq
        orgs_by_id = Organization.where(id: org_ids).index_by(&:id)

        security_campaigns_by_org_id = security_campaigns.group_by(&:organization_id)

        filtered_alerts = []
        security_campaigns_by_org_id.each do |org_id, campaigns|
          org = orgs_by_id[org_id]
          campaign_ids = campaigns.map(&:id)
          alerts_in_campaigns = campaign_alerts.select { |ca| campaign_ids.include?(ca.security_campaign_id) }

          # Find all repositories that are part of the security campaigns
          repo_ids_in_campaigns = alerts_in_campaigns.map(&:repository_id).uniq
          # Filter the repos to the repos in the org
          repos_scope = targetable_repositories(org).where(id: repo_ids_in_campaigns)
          repos_scope = filter_repositories(strategy:, scope: repos_scope) unless strategy.nil?

          repo_ids_in_org = GitHub.dogstats.distribution_time("security_campaigns.alert_load", tags: ["kind:repositories_for_org"]) do
            repos_scope.pluck(:id)
          end

          # Remove all alerts where the repos is not in the org
          alerts_in_correct_org = alerts_in_campaigns.select { |ca| repo_ids_in_org.include?(ca.repository_id) }

          filtered_alerts.concat(alerts_in_correct_org)

          # Log any discrepencies for tracking
          if repo_ids_in_campaigns.size != repo_ids_in_org.size
            repo_ids_in_campaigns.select { |id| !repo_ids_in_org.include?(id) }.each do |repo_id|
              GitHub.dogstats.increment("security_campaigns.repos_not_in_org")
              GitHub.logger.info("Filtered away repository not in org",
                "code.function" => "filter_campaign_alerts",
                "gh.repo.id" => repo_id,
                "gh.org.id" => org_id,
                "gh.security_campaign_ids" => campaign_ids,
              )
            end
          end

        end
        filtered_alerts
      end
    end
  end
end
