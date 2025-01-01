# typed: strict
# frozen_string_literal: true

# Contains multiple AlertLink objects, representing links between scanning alerts and branches or pull requests.
# Alert links are loaded from turboscan and then enriched with branch/PR data.
module CodeScanning
  class AlertLinks
    extend GitHub::ResilienceMixin

    sig { params(links: T::Hash[[Integer, Integer], T::Array[AlertLink]]).void }
    def initialize(links)
      @links = links
    end

    sig { params(repo_id: Integer, alert_number: Integer).returns(T::Array[AlertLink]) }
    def get_links(repo_id:, alert_number:)
      @links[[repo_id, alert_number]] || []
    end

    # Load all alert links for the given list of repositories and alert numbers.
    #
    # Accepts an array of RepoAndAlert objects.
    sig do
      params(
        repos_and_alerts: T::Array[RepoAlertTuple],
      ).returns(AlertLinks)
    end
    def self.load(repos_and_alerts)
      return new({}) if repos_and_alerts.empty?

      response = GitHub::Turboscan.get_links_for_alerts({
        repos_and_alerts: repos_and_alerts.map do |r|
          Turboscan::Proto::RepoNumber.new(repository_id: r.repository_id, number: r.alert_number)
        end
      })

      if response.blank? || response.error.present?
        # If this fails, we want to degrade gracefully and not show any links.
        return new({})
      end

      turboscan_links = response.data.links
      pull_request_links, branch_links = turboscan_links.partition { |l| l.pull_request_id.present? && !l.pull_request_id.zero? }

      # Fetch associated pull requests
      pull_request_ids = pull_request_links.map { |l| l.pull_request_id }
      pull_requests = with_database_error_fallback(fallback: {}) do
        PullRequest.includes(:issue, :repository).not_spammy.where(id: pull_request_ids).index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      # Fetch associated repositories
      repository_ids = repos_and_alerts.map(&:repository_id).uniq
      repositories = with_database_error_fallback(fallback: {}) do
        Repository.where(id: repository_ids).index_by(&:id)
      end

      # Fetch associated branches
      alert_link_branches = branch_links.filter_map do |l|
        next if l.repository_id.blank? || l.ref_name_bytes.blank?

        branch = repositories[l.repository_id]&.heads&.find(l.ref_name_bytes)
        next unless branch&.exist?

        [[l.repository_id, l.ref_name_bytes], branch]
      end.to_h

      links = turboscan_links
        .group_by { |l| [l.repository_id, l.alert_number] }
        .transform_values do |links|
          links.uniq { |l| [l.ref_name_bytes, l.pull_request_id] }.map do |link|
            CodeScanning::AlertLink.new(
              repository_id: link.repository_id,
              alert_number: link.alert_number,
              branch: alert_link_branches[[link.repository_id, link.ref_name_bytes]],
              pull_request: pull_requests[link.pull_request_id]
            )
          end
        end

      new(links)
    end

    # Load all alert links for the given alert.
    # The limit parameter is used to limit the number of links returned and has a default value of 15.
    #
    # Accepts a repository id and an alert number.
    sig { params(repository_id: Integer, alert_number: Integer, limit: Integer).returns(T::Array[AlertLink]) }
    def self.load_for_single_alert(repository_id:, alert_number:, limit: 15)
      repo_alert_tuple = CodeScanning::RepoAlertTuple.new(repository_id:, alert_number:)
      links = CodeScanning::AlertLinks.load([repo_alert_tuple]).get_links(repo_id: repository_id, alert_number:)
        .sort_by { |link| link.pull_request? ? 0 : 1 }

      # We don't expect users to have more than 15 alert links, so we simply prioritize PRs over branches,
      # which is straightforward to do as they've already been sorted to have the PRs first
      # Not optimized, but good enough.
      # See: https://github.com/github/code-scanning/issues/17932#issuecomment-2739767288
      if links.size > limit
        GitHub.logger.info("Capping alert links to #{limit}",
          alert_number: alert_number,
          repository_id: repository_id,
          n_links: links.size,
        )
        links = links.take(limit)
      end

      links
    end
  end
end
