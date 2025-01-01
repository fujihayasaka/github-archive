# typed: false
# frozen_string_literal: true

module Events
  class GollumView < View
    TOTAL_VISIBLE_PAGES = 3

    class Page
      def initialize(event, payload)
        @event = event
        @payload = payload
      end

      def action
        Stratocaster::EventPayload.new(@payload).action
      end

      def capital_action
        action.to_s.capitalize
      end

      def created?
        action&.to_sym == :created
      end

      def summary
        @payload[:summary]
      end

      def wiki_title
        @payload[:title]
      end

      def url
        @payload[:url] ||
          "/#{@event.repo_nwo}/wiki/#{escape_url_fragment(page_cname)}"
      end

      def compare_url
        return unless @payload[:sha]
        sha = @payload[:sha].first(7)
        "#{url}/_compare/#{sha}^...#{sha}"
      end

      private

      def page_cname
        GitHub::Unsullied::Page.cname(@payload[:page_name].to_s)
      end

      def escape_url_fragment(s)
        return "" if s.blank?
        escaped = CGI.escape(s)
        escaped.gsub! /%2F/, "/"
        escaped
      end
    end

    def title_text
      parts = [actor_text, action, "a wiki page in", repo_text]
      parts.compact.join(" ")
    end

    def action
      pages.size == 1 ? pages.first.action : :edited
    end

    def remaining_page_count
      all_pages.size - TOTAL_VISIBLE_PAGES
    end

    def pages
      all_pages.first(TOTAL_VISIBLE_PAGES)
    end

    def more_pages?
      all_pages.size > TOTAL_VISIBLE_PAGES
    end

    def wiki_path
      if repo_nwo.present?
        "/#{repo_nwo}/wiki"
      else
        "/"
      end
    end

    private

    def all_pages
      @all_pages ||=
        begin
          pages = payload.key?(:page_name) ? [payload] : payload[:pages]
          (pages || []).map { |hash| Page.new(self, hash) }
        end
    end
  end
end
