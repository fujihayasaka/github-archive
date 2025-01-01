# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class AlertMentionFilter < NodeFilter
    NWO = /(?<nwo>#{::GitHub::HTML::IssueMentionFilter::NWO})/
    ALERT_ID = /(?<alert_id>\d+)\b/.freeze

    class Item
      attr_reader :alert_id, :alert_type, :nwo

      def initialize(match, state_text = nil)
        @alert_id = Integer(match[:alert_id])
        @alert_type = match[:alert_type]&.downcase
        @nwo = match.named_captures.keys.include?("nwo") ? match[:nwo] : nil
        @state_text = state_text
      end

      def json_data
        h = { alert_id: @alert_id, alert_type: @alert_type }
        h[:nwo] = @nwo if @nwo.present?
        h.to_json
      end

      def completed?
        raise TypeError, "Can't convert state[#{@state_text.inspect}] to completed or not if it is empty." if @state_text.blank?
        !!(@state_text =~ TaskList::Filter::CompletePattern)
      end
    end

    def self.enabled?(context)
      context[:unfurl_references] && GitHub.code_scanning_enabled?
    end

    def selector
      Goomba::Selector.new(match: ":text, a[href^='#{GitHub.url}']",
        reject: "pre :text, code :text, a :text, blockquote :text")
    end

    def call(node)
      if is_element_node?(node) # HTML tag
        call_anchor(node) if node.tag == :a
      end
    end

    def self.security_alert_url_pattern
      %r{\A(#{Regexp.escape(GitHub.url)})?/#{NWO}/security/(?<alert_type>code-scanning)/#{ALERT_ID}(\?.*)?}
    end

    private

    def call_anchor(node)
      return unless node_is_a_bare_link?(node)
      if md = node["href"].match(self.class.security_alert_url_pattern)
        node["gh:alert-mention"] = Item.new(md).json_data
      end
      nil
    end

    def node_is_a_bare_link?(node)
      node.inner_html == node["href"]
    end
  end
end
