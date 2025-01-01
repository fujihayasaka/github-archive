# typed: true
# frozen_string_literal: true
module GitHub::Goomba
  class DependabotAlertMentionFilter < NodeFilter
    NWO = /(?<nwo>#{::GitHub::HTML::IssueMentionFilter::NWO})/.freeze
    ALERT_NUMBER = /(?<alert_number>\d+)\b/.freeze

    class Item
      attr_reader :alert_number, :nwo

      def initialize(match)
        @alert_number = Integer(match[:alert_number])
        @nwo = match.named_captures.keys.include?("nwo") ? match[:nwo] : nil
      end

      def json_data
        h = { alert_number: @alert_number }
        h[:nwo] = @nwo if @nwo.present?
        h.to_json
      end
    end

    def self.alert_url_pattern
      %r{\A(#{Regexp.escape(GitHub.url)})?/#{NWO}/security/dependabot/#{ALERT_NUMBER}(\?.*)?}.freeze
    end

    def self.enabled?(context)
      return false unless context[:unfurl_references]
      SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
    end

    def selector
      Goomba::Selector.new(match: "a[href^='#{GitHub.url}']")
    end

    def call(node)
      call_anchor(node)
    end

    private

    def call_anchor(node)
      return unless node_is_a_bare_link?(node)
      if md = node["href"].match(self.class.alert_url_pattern)
        node["gh:dependabot-alert-mention"] = Item.new(md).json_data
      end
      nil
    end

    def node_is_a_bare_link?(node)
      node.inner_html == node["href"]
    end
  end
end
