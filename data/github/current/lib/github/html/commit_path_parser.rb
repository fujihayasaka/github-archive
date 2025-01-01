# typed: false
# frozen_string_literal: true

module GitHub::HTML
  class CommitPathParser
    USERID_REGEX = /\A-?[a-z0-9][a-z0-9\-\_]*\z/i
    REPO_REGEX = /\A(?:\w|\.|\-)+\z/i
    COMMIT_PATH = %r[\A/([^/]+)/([^/]+)/commit/(.+)\z]
    COMPARE_PATH = %r[\A/([^/]+)/([^/]+)/compare/(.+)\z]
    PULL_COMMIT_PATH = %r[\A/([^/]+)/([^/]+)/pull/(\d+)/commits/((?:[^.]|\.{2,})+)\z]
    SLASH = "/"
    COMMIT_ACTIONS_WITHOUT_PARAMS = %w(
      checks_state_summary
      hovercard
      rollup
      show_partial
    ).freeze
    COMMIT_ACTIONS_WITH_PARAMS = %w(
      _render_node
      checks
    ).freeze

    def initialize(href)
      @href = href
    end

    # Public: Transform the href into params that the rails router would generate.
    def params
      return unless valid_github_url?
      return unless valid_nwo?

      if match_data = COMMIT_PATH.match(uri.path)
        user_id, repository, path_fragment = match_data.captures

        name, file_path = path_fragment.split(SLASH, 2)
        return if file_path&.empty?
        return if reserved_commit_action_path?(file_path)

        name, format = name&.split(".")
        return if format

        {
          controller: "commit",
          action: "show",
          user_id: user_id,
          repository: repository,
          name: name,
          path: file_path && Rack::Utils.unescape_path(file_path),
        }.compact
      elsif match_data = COMPARE_PATH.match(uri.path)
        user_id, repository, range = match_data.captures

        {
          controller: "compare",
          action: "show",
          user_id: user_id,
          repository: repository,
          range: range && Rack::Utils.unescape_path(range),
        }
      elsif match_data = PULL_COMMIT_PATH.match(uri.path)
        user_id, repository, pull_number, range = match_data.captures

        {
          controller: "pull_requests",
          action: "commits",
          tab: "commits",
          user_id: user_id,
          repository: repository,
          range: range,
          id: pull_number
        }
      end
    end

    private

    attr_reader :href

    def valid_nwo?
      return false if uri_path_parts.size < 2

      user_id, repository = uri_path_parts
      USERID_REGEX.match?(user_id) && REPO_REGEX.match?(repository)
    end

    def uri
      return @_uri if defined?(@_uri)
      @_uri = URI.parse(href)
    rescue URI::InvalidURIError
      @_uri = nil
    end

    def valid_github_url?
      valid_uri? && is_github_url?
    end

    def valid_uri?
      uri.present?
    end

    def is_github_url?
      uri.host == GitHub.host_name_with_tenant && uri.scheme == GitHub.scheme
    end

    def uri_path_parts
      uri.path.delete_prefix(SLASH).split(SLASH)
    end

    def reserved_commit_action_path?(file_path)
      return false unless file_path
      return true if file_path.in?(COMMIT_ACTIONS_WITHOUT_PARAMS)

      first_path_segment = file_path.split(SLASH).first
      return true if first_path_segment.in?(COMMIT_ACTIONS_WITH_PARAMS)

      false
    end
  end
end
