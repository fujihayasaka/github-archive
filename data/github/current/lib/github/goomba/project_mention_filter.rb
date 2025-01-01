# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitHub::Goomba
  # Matches link references to projects in user-supplied content.
  #
  # Link target references are transformed by adding an attribute to the <a>
  # tag. Given input like this:
  #
  #   <a href="https://github.com/orgs/github/projects/1/views/1">My project</a>
  #
  # The following output will be given, ignoring whitespace differences:
  #
  #   <a href="https://github.com/orgs/github/projects/1/views/1"
  #      gh:project-mention='{"owner_type":"orgs","owner":"github","number":1}'>
  #      My project</a>
  #
  # The tag is unchanged except for having the gh:project-mention attribute added
  # to it. Because we don't replace the node, but instead modify it in place,
  # other node filters can recurse into its contents and further process them.
  # This concern is unique to link target references, as plain text references,
  # being plain text, cannot contain any other markup that might be recursed
  # into.
  #
  # The 'owner_type' element of the JSON object is the owner type from the URL,
  # either org or user, and is always present.
  #
  # The 'owner' and 'number' elements are likewise parsed from the URL and are always present.
  #
  # Link targets are of special note because they will result not only when a
  # user enters an explicit link in their comment's Markdown source, but also if
  # they simply paste a GitHub project URL into their comment, as
  # it will be autolinked by our Markdown processor. The processing specific to
  # this occurs in GitHub::Goomba::Async::ProjectMentionFilter.
  #
  class ProjectMentionFilter < NodeFilter
    # Example:
    # https://github.com/orgs/github/projects/4017/views/14
    # https://github.com/users/github/projects/4017/views/14
    # https://github.com/users/github/projects/4017
    # https://github.com/orgs/github/projects/5714/views/1?pane=info&statusUpdateId=7964
    # DOES NOT MATCH
    # https://github.com/orgs/github/projects/35/assets/8675309/1234567a-e6a7-40ba-b656-654321c0ad46
    NAME = /(\w+(?:-\w+)*)/
    PROJECT_REFERENCE = /(?<owner_type>(?:orgs|users))\/(?<owner>#{NAME})\/(?:projects)\/(?<number>(?:\d+))?+(?!\/assets)(\/(?:views)\/(?<view>(?:\d+)))?/.freeze

    def selector
      Goomba::Selector.new(match: "a[href^='#{GitHub.url}']", reject: "pre :text, code :text, a :text, :text")
    end

    def self.feature_flags
      [:project_link_unfurling]
    end

    def self.enabled?(context)
      return false unless current_user = context[:current_user]
      current_user.feature_enabled?(:project_link_unfurling)
    end

    def call(node)
      # Only process valid URLs
      return unless node["href"] =~ URI::RFC2396_PARSER.regexp[:ABS_URI]
      return unless md = node["href"].match(PROJECT_REFERENCE)

      params = parse_parameters(node["href"])

      # When the project side-panel has an issue in focus, we want to treat the link as an issue mention
      side_panel_reference = params&.dig("issue")
      if side_panel_reference
        side_panel_issue_mention(node, side_panel_reference)
        return
      end

      # Otherwise, we treat the link as a project mention :)
      node["gh:project-mention"] = {
        owner: md[:owner],
        number: md[:number],
        view: md[:view],
        status_update_id: params&.dig("statusUpdateId"),
      }.to_json

      nil
    end

    def parse_parameters(url)
      begin
        params = Rack::Utils.parse_query(URI(url).query)
      rescue URI::InvalidURIError
        nil
      end
    end

    def side_panel_issue_mention(node, issue_param)
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
