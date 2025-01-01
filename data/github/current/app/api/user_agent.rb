# typed: true
# frozen_string_literal: true

module Api

  # Represents user agent information parsed from a
  # User-Agent string.
  class UserAgent

    # Internal: Parses version info from a MAJOR.MINOR.x.x format.
    class Version

      def initialize(version)
        @version = version.to_s

        @major, @minor, @patch = @version.split(".").first(3)
      end

      def major
        @major.to_i
      end

      def minor
        @minor.to_i
      end

      def patch
        @patch.to_i
      end
    end

    BROWSER_PATTERN                 = /Safari|Firefox/.freeze
    CLI_PATTERN                     = /curl|Wget/.freeze
    GITHUB_ANDROID_PATTERN          = %r{GitHubAndroid/?(?<version>\d+.\d+)?}.freeze
    GITHUB_ISSUES_PATTERN           = %r{GitHubIssues/?(?<version>\d+.\d+)?}.freeze
    GITHUB_VISUAL_STUDIO_PATTERN    = %r{(GitHubVisualStudio|VSTeamExplorer-GitHub)/?(?<version>\d+.\d+.\d+.\d+)?}.freeze
    GITHUB_GRAPHQL_EXPLORER_PATTERN = %r{GitHubGraphQLExplorer/[0-9a-f]{40}}.freeze
    GITHUB_DESKTOP_PATTERN          = %r{GitHubDesktop(?:-dev)?/?(?<version>\d+.\d+.?\d*)?}.freeze

    def initialize(string)
      @string = string
    end

    def string
      @string.to_s
    end
    alias :to_s :string

    # Indicates the user agent is a GitHub Desktop client.
    def github_desktop?
      matches?(GITHUB_DESKTOP_PATTERN)
    end

    # Indicates the version number (if any) for a desktop client.
    def github_app_version
      @github_app_version
    end

    # Indicates the user agent is a known command line interface client.
    def cli?
      matches?(CLI_PATTERN)
    end

    # Indicates the user agent is a known browser client.
    def browser?
      matches?(BROWSER_PATTERN)
    end

    # Indicates if the user agent is the GitHub Issues app.
    def github_issues?
      matches?(GITHUB_ISSUES_PATTERN)
    end

    # Indicates if the user agent is the GitHub Issues app.
    def github_android?
      matches?(GITHUB_ANDROID_PATTERN)
    end

    # Indicates if the user agent is the GitHub VisualStudio app.
    def github_visual_studio?
      matches?(GITHUB_VISUAL_STUDIO_PATTERN)
    end

    def github_graphql_explorer?
      matches?(GITHUB_GRAPHQL_EXPLORER_PATTERN)
    end

    # Is the request coming from the Mac platform?
    def running_mac_platform?
      string =~ /Macintosh/
    end

    # Is the request coming from the Windows platform?
    def running_windows_platform?
      string =~ /Windows/
    end

    def group_syncer?
      string =~ /group-syncer/
    end

    private

    def matches?(pattern)
      if match_data = pattern.match(string)
        if match_data.names.include?("version")
          @github_app_version = Version.new(match_data[:version])
        end

        true
      else
        false
      end
    end
  end
end
