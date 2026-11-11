# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class IssueDashboardMentionFilter < NodeFilter
    def selector
      Goomba::Selector.new(match: "a[href^='#{GitHub.url}/issues']")
    end

    def call(node)
      # Only process valid URLs
      return unless node["href"] =~ URI::RFC2396_PARSER.regexp[:ABS_URI]

      params = parse_parameters(node["href"])

      # When the Issues dashboard side-panel has an issue in focus, we want to treat the page's URL as an issue mention
      issue_param = params&.dig("issue")
      if issue_param
        issue_mention_node(node:, issue_param:)
        return
      end

      nil
    end

    def parse_parameters(url)
      begin
        params = Rack::Utils.parse_query(URI(url).query)
      rescue URI::InvalidURIError
        nil
      end
    end

    def issue_mention_node(node:, issue_param:)
      owner, repository_name, issue_number = issue_param.split("|")
      nwo = "#{owner}/#{repository_name}" # rubocop:disable GitHub/DoNotAllowLogin owner is display_login from the URL's search params
      number = issue_number
      anchor = nil

      node["gh:issue-mention"] = {
        nwo:,
        number:,
        anchor:,
      }.to_json
    end
  end
end
