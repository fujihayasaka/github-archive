# typed: strict
# frozen_string_literal: true

# This class contains several security campaigns enriched with information about grouped alert counts.
module SecurityCampaigns
  class CampaignWithGroupedCounts < CampaignBase
    class Cursor < T::ImmutableStruct

      extend T::Generic
      Elem = type_member

      sig do
        type_parameters(:T).
        params(
          items: T::Array[T.all(T.type_parameter(:T), Kernel)],
          after_cursor: T.nilable(String),
          before_cursor: T.nilable(String),
          page_size: Integer,
        ).returns(
          Cursor[T.type_parameter(:T)]
        )
      end
      def self.page(items:, after_cursor:, before_cursor:, page_size: 10)
        from = if after_cursor.present?
          items.index { |item| item.to_s == after_cursor }
        elsif before_cursor.present?
          # if we find the before cursor element then subtract page_size from the index
          items.index { |item| item.to_s == before_cursor }&.- page_size
        end
        # from must be non-nil and > 0 as negative numbers index from the end of an array
        from = 0 if from.nil? || from < 0
        to = from + page_size

        page = items[from...to]

        # there should only be a next cursor if we are not past the end of the list
        next_cursor = items[to]&.to_s if to <= items.size
        # if from is zero then there are no more elements to show before this
        prev_cursor = items[[0, from - 1].max]&.to_s if from > 0

        Cursor.new(items: page || [], next: next_cursor, prev: prev_cursor)
      end

      const :items, T::Array[Elem]
      const :next, T.nilable(String)
      const :prev, T.nilable(String)
    end

    class GroupCounts < T::Struct
      const :title, String
      const :repositories, T::Array[Repository]
      const :open_count, Integer
      const :closed_count, Integer
      const :open_with_links_count, Integer
    end

    sig { returns(T::Array[GroupCounts]) }
    attr_reader :groups

    sig { returns(T.nilable(String)) }
    attr_reader :next_cursor

    sig { returns(T.nilable(String)) }
    attr_reader :prev_cursor

    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        open_count: Integer,
        closed_count: Integer,
        open_with_links_count: Integer,
        groups: T::Array[GroupCounts],
        next_cursor: T.nilable(String),
        prev_cursor: T.nilable(String),
      ).void
    end
    def initialize(security_campaign, open_count, closed_count, open_with_links_count, groups:, next_cursor: nil, prev_cursor: nil)
      super(security_campaign, open_count, closed_count, open_with_links_count)
      @groups = groups
      @next_cursor = next_cursor
      @prev_cursor = prev_cursor
    end

    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        user: User,
        query_string: T.nilable(String),
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
        query_service: CodeScanning::AlertQueryService,
      ).returns(CampaignWithGroupedCounts)
    end
    def self.load(security_campaign:, user:, query_string:, after_cursor:, before_cursor:, query_service:)
      query = Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query_string)

      ## This is related to new data model spike for security campaigns
      ## We need to add more filters used in load_campaign_alerts to the alert query service
      if user.feature_enabled?(:security_campaigns_read_without_alerts_limit)
        return campaign_with_grouped_counts(security_campaign:, after_cursor:, before_cursor:, query_service:, query:)
      end

      campaign_alerts = SecurityCampaigns::CampaignBase::load_campaign_alerts([security_campaign], repo: nil, strategy: query_service.strategy, alert_numbers: nil)

      tags = ["kind:turboscan_grouped_counts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.grouped_alert_load", tags: tags) do
        repo_numbers_for_campaign = SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(campaign_alerts)

        next CampaignWithGroupedCounts.new(security_campaign, 0, 0, 0, groups: []) if repo_numbers_for_campaign.empty?

        filter = query_service.build_alerts_filter

        alerts_response = GitHub::Turboscan.counts_by_repo_numbers({
            owner_ids: [security_campaign.organization_id],
            repo_numbers: repo_numbers_for_campaign,
            filter:,
        })

        raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

        data = alerts_response.data

        next CampaignWithGroupedCounts.new(security_campaign, 0, 0, 0, groups: []) if data.nil?

        repo_counts = data.repository_counts

        # remove counts not relevant to the query
        repo_counts = repo_counts.filter do |repo_count|
          (query.open? && repo_count.open_count.nonzero?) || (query.closed? && repo_count.closed_count.nonzero?)
        end if query.open? || query.closed?

        ordered_repositories_scope = targetable_repositories(security_campaign.organization).order(name: :asc)

        # avoid an empty IN () query when there are no items
        repository_ids = if repo_counts.present?
          # avoid a full repository load to start with, just select the IDs in the order we want to display them
          ordered_repositories_scope.where(id: repo_counts.map(&:repository_id)).pluck(:id)
        else
          []
        end

        repo_counts = repo_counts.index_by(&:repository_id)

        cursor = Cursor.page(items: repository_ids, after_cursor:, before_cursor:)

        groups = if cursor.items.present?
          # fully load the page of repositories
          ordered_repositories_scope.where(id: cursor.items).map do |repository|
            repo_count = repo_counts[repository.id]

            GroupCounts.new(
              title: repository.name,
              repositories: [repository],
              open_count: repo_count&.open_count || 0,
              closed_count: repo_count&.closed_count || 0,
              open_with_links_count: repo_count&.open_with_links_count || 0,
            )
          end
        end

        CampaignWithGroupedCounts.new(security_campaign, data.open_count, data.closed_count, data.open_with_links_count, next_cursor: cursor.next, prev_cursor: cursor.prev, groups: groups || [])
      end
    end

    sig do
      params(
        security_campaign: SecurityCampaigns::SecurityCampaign,
        after_cursor: T.nilable(String),
        before_cursor: T.nilable(String),
        query_service: CodeScanning::AlertQueryService,
        query: Search::Queries::SecurityCenter::CodeScanningOrgQuery,
      ).returns(CampaignWithGroupedCounts)
    end
    private_class_method def self.campaign_with_grouped_counts(security_campaign:, after_cursor:, before_cursor:, query_service:, query:)
      tags = ["kind:turboscan_grouped_counts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.grouped_alert_load", tags: tags) do
        alerts_response = query_service.repo_counts_by_campaigns
        raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

        data = alerts_response.data

        next CampaignWithGroupedCounts.new(security_campaign, 0, 0, 0, groups: []) if data.nil?

        repo_counts = data.repository_counts

        # remove counts not relevant to the query
        repo_counts = repo_counts.filter do |repo_count|
          (query.open? && repo_count.open_count.nonzero?) || (query.closed? && repo_count.closed_count.nonzero?)
        end if query.open? || query.closed?

        ordered_repositories_scope = targetable_repositories(security_campaign.organization).order(name: :asc)

        # avoid an empty IN () query when there are no items
        repository_ids = if repo_counts.present?
          # avoid a full repository load to start with, just select the IDs in the order we want to display them
          ordered_repositories_scope.where(id: repo_counts.map(&:repository_id)).pluck(:id)
        else
          []
        end

        repo_counts = repo_counts.index_by(&:repository_id)

        cursor = Cursor.page(items: repository_ids, after_cursor:, before_cursor:)

        groups = if cursor.items.present?
          # fully load the page of repositories
          ordered_repositories_scope.where(id: cursor.items).map do |repository|
            repo_count = repo_counts[repository.id]

            GroupCounts.new(
              title: repository.name,
              repositories: [repository],
              open_count: repo_count&.open_count || 0,
              closed_count: repo_count&.closed_count || 0,
              open_with_links_count: repo_count&.open_with_links_count || 0,
            )
          end
        end

        CampaignWithGroupedCounts.new(security_campaign, data.open_count, data.closed_count, data.open_with_links_count, next_cursor: cursor.next, prev_cursor: cursor.prev, groups: groups || [])
      end
    end
  end
end
