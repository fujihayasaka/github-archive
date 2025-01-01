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

      pull_request_ids = turboscan_links.map { |l| l.pull_request_id }.compact
      pull_requests = with_database_error_fallback(fallback: {}) do
        PullRequest.includes(:issue, :repository).not_spammy.where(id: pull_request_ids).index_by(&:id)
      end

      links = turboscan_links
        .group_by { |l| [l.repository_id, l.alert_number] }
        .transform_values do |links|
          links.uniq { |l| [l.ref_name_bytes, l.pull_request_id] }.map do |link|
            CodeScanning::AlertLink.new(
              repository_id: link.repository_id,
              alert_number: link.alert_number,
              branch: link.ref_name_bytes.presence,
              pull_request: pull_requests[link.pull_request_id]
            )
          end
        end

      new(links)
    end
  end
end
