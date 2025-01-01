# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module GitHub::Goomba::Async
  class DependabotAlertMentionFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "a[gh|dependabot-alert-mention]")
    include OcticonsHelper
    include GitHub::Goomba::Reference::Helpers

    class AlertsMap
      def initialize
        @hash = {}
      end

      def get(alert_number, nwo)
        @hash[key(alert_number, nwo)]
      end

      def set(alert_number, nwo, alert)
        @hash[key(alert_number, nwo)] = alert
      end

      private

      def key(alert_number, nwo)
        [alert_number.to_s, nwo]
      end
    end

    def initialize(*args)
      super
      @alerts_map = AlertsMap.new
      @repo_map = {}
    end

    def selector
      SELECTOR
    end

    def self.enabled?(context)
      GitHub::Goomba::DependabotAlertMentionFilter.enabled?(context)
    end

    def async_scan
      async_alerts = @nodes.map do |node|
        alert_number, nwo = extract_data(node["gh:dependabot-alert-mention"])
        next unless alert_number && nwo

        async_find_repository(nwo).then do |repo|
          next unless repo
          next if @alerts_map.get(alert_number, nwo)

          # If the DB fails, this will set alert to nil, the same way we would as if the alert wasn't found
          alert = begin
            repo.repository_vulnerability_alerts.where(number: alert_number).first
          rescue *GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST => e
            Failbot.report(e)
            nil
          end

          @alerts_map.set(alert_number, nwo, alert)
          @repo_map[nwo] = repo
        end
      end

      Promise.all(async_alerts)
    end

    def call(node)
      call_anchor_tag(node)
    end

    private

    # See GitHub::Goomba::NodeFilter for docs on the various return values.
    def call_anchor_tag(node)
      href, data = node["href"], node["gh:dependabot-alert-mention"]
      node.remove_attribute("gh:dependabot-alert-mention")

      alert_number, nwo = extract_data(data)
      alert = @alerts_map.get(alert_number, nwo)
      repo = @repo_map[nwo]

      # return the original node if we didn't find an alert or repo
      return nil unless alert && repo

      # returns HTML for viewers that are both authorized and unauthorized to see the alert richly rendered
      repository_resource_reference_wrapper(alert) do |wrapper|
        wrapper.authorized { dependabot_alert_link(alert, repo) }
        # the nodes original HTML content is the fallback when a user can't see an unfurled
        # dependabot alert link
        wrapper.unauthorized { node.to_html }
      end
    end

    def dependabot_alert_link(alert, repo)
      title = alert.title
      path = UrlHelpers.repository_alert_path(user_id: repo.owner_display_login, repository: repo.name, number: alert.number)
      attrs = { data: HovercardHelper.hovercard_data_attributes_for_dependabot_alert(repo.owner_display_login, repo.name, alert.number) }
      link = ActionController::Base.helpers.link_to(title.truncate(100), path, attrs)

      before = octicon("shield", class: "color-fg-muted mr-1")
      reference = EscapeHelper.safe_join([before, link])

      ActionController::Base.helpers.content_tag(:span, reference, { class: "reference issue-link" })
    end

    def extract_data(data)
      data = JSON.parse(data)
      alert_number, nwo = data["alert_number"].to_i, data["nwo"]
    end
  end
end
