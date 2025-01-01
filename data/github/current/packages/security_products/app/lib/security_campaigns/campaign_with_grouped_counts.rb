# typed: strict
# frozen_string_literal: true

# This class contains several security campaigns enriched with information about grouped alert counts.
module SecurityCampaigns
  class CampaignWithGroupedCounts < CampaignBase
    PAGE_SIZE_DEFAULT = 10

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
        security_campaign: SecurityCampaign,
        counts: CampaignCounts,
        groups: T::Array[GroupCounts],
        next_cursor: T.nilable(String),
        prev_cursor: T.nilable(String),
      ).void
    end
    def initialize(security_campaign, counts, groups:, next_cursor: nil, prev_cursor: nil)
      super(security_campaign, counts)
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
        page_size: Integer,
      ).returns(CampaignWithGroupedCounts)
    end
    def self.load(security_campaign:, user:, query_string:, after_cursor:, before_cursor:, query_service:, page_size: PAGE_SIZE_DEFAULT)
      query = Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query_string)

      tags = ["kind:turboscan_grouped_counts_org"]
      GitHub.dogstats.distribution_time("security_campaigns.grouped_alert_load", tags: tags) do
        repo_counts, has_error, alerts_response = query_service.counts_by_repo
        raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if has_error

        alerts_response = T.let(alerts_response, T.nilable(Twirp::ClientResp[Turboscan::Proto::CountsByRepoResponse]))

        next CampaignWithGroupedCounts.new(security_campaign, CampaignCounts.empty, groups: []) if alerts_response.nil?

        repo_counts = T.let(repo_counts, T::Array[Turboscan::Proto::CountsByRepoResponse::RepositoryCounts])

        next CampaignWithGroupedCounts.new(security_campaign, CampaignCounts.empty, groups: []) if repo_counts.empty?

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

        cursor = CodeScanning::InMemoryCursor.page(items: repository_ids, after_cursor:, before_cursor:, page_size:)

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

        counts = CampaignCounts.new(
          open_count: alerts_response.data.open_count,
          closed_count: alerts_response.data.closed_count,
          open_with_links_count: alerts_response.data.open_with_links_count
        )

        CampaignWithGroupedCounts.new(security_campaign, counts, next_cursor: cursor.next, prev_cursor: cursor.prev, groups: groups || [])
      end
    end
  end
end
