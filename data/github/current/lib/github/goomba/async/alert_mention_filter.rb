# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module GitHub::Goomba::Async
  class AlertMentionFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "a[gh|alert-mention]")
    MAX_MENTIONS = 200
    include OcticonsHelper
    include GitHub::Goomba::Reference::Helpers

    class AlertsMap
      def initialize
        @hash = {}
      end

      def get(alert_id, nwo)
        @hash[key(alert_id, nwo)]
      end

      def set(alert_id, nwo, short_alert)
        @hash[key(alert_id, nwo)] = short_alert
      end

      private

      def key(alert_id, nwo)
        [alert_id.to_s, nwo]
      end
    end

    def initialize(*args)
      super
      @alerts_map = AlertsMap.new
    end

    def selector
      SELECTOR
    end

    def self.enabled?(context)
      GitHub::Goomba::AlertMentionFilter.enabled?(context)
    end

    def async_scan
      count = 0
      async_alerts = @nodes.map do |node|
        alert_id, nwo = extract_data(node["gh:alert-mention"])

        async_find_repository(nwo).then do |repo|
          next unless repo

          count += 1
          next unless count <= MAX_MENTIONS
          Platform::Loaders::Turboscan::CodeScanningShortAlerts.load(repo.id, alert_id).then do |short_alert|
            @alerts_map.set(alert_id, nwo, short_alert.merge(repo: repo)) if short_alert.present?
          end
        end
      end

      Promise.all(async_alerts).then do |res|
        # Report total count of Mentions so we can understand how close the users are to this limit.
        GitHub.dogstats.distribution("alert_mention_filter.mentions", count)
        res
      end
    end

    def extract_data(data)
      data = JSON.parse(data)
      alert_id, nwo = data["alert_id"], data["nwo"]
    end

    def call(node)
      call_anchor_tag(node)
    end

    def call_anchor_tag(node)
      data = node["gh:alert-mention"]
      node.remove_attribute("gh:alert-mention")
      alert_id, nwo = extract_data(data)
      short_alert = @alerts_map.get(alert_id, nwo)
      return nil unless short_alert

      repo = short_alert[:repo]
      title = "#{short_alert[:title]}"
      repository_reference_wrapper(repo, check_type: :code_scanning) do |wrapper|
        wrapper.authorized { code_scanning_alert_link(alert_id, repo, title) }
        wrapper.unauthorized { node.to_html }
      end
    end

    def code_scanning_alert_link(alert_id, repo, title)
      attrs = {
        "class" => "js-security-alert-link",
      }.merge(data: HovercardHelper.hovercard_data_attributes_for_security_alert(repo.owner_display_login, repo.name, alert_id))

      path = UrlHelpers.repository_code_scanning_result_path(repo.owner_display_login, repo, number: alert_id)
      link = ActionController::Base.helpers.link_to(title.truncate(100), path, attrs)
      before = octicon("shield", class: "color-fg-muted mr-1")
      reference = EscapeHelper.safe_join([before, link])

      ActionController::Base.helpers.content_tag(:span, reference, { class: "reference" })
    end
  end
end
