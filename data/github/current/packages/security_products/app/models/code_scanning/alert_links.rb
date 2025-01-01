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

      turboscan_links = T.must(response.data).links
      pull_request_links, branch_links = turboscan_links.partition { |l| l.pull_request_id.present? && !l.pull_request_id.zero? }

      # Fetch associated pull requests
      pull_request_ids = pull_request_links.map { |l| l.pull_request_id }
      pull_requests = with_database_error_fallback(fallback: {}) do
        PullRequest.includes(:issue, :repository).not_spammy.where(id: pull_request_ids).index_by(&:id)
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
  end
end
