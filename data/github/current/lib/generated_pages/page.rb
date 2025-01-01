# typed: false
# frozen_string_literal: true

module GeneratedPages
  class Page < Mustache
    include ApplicationHelper
    include AvatarHelper

    def initialize(page_params)
      @page_params = page_params
      @user        = User.find_by_login(@page_params[:owner].to_s)
      @repo        = Repository.find_by_id(@page_params[:repo_id])

      template_file = File.join(Rails.root, "public", "themes",
                                @page_params[:theme_slug],
                                "page.#{self.class.template_extension}")
      self.template = File.read(template_file)
    end

    def asset_path_prefix
      @page_params[:preview] ? @page_params[:asset_path_prefix] : ""
    end

    def repository_url
      super(@repo)
    end

    def project_title
      @page_params[:project]
    end

    def project_tagline
      @page_params[:tagline]
    end

    def owner_url
      github_url_for @page_params[:owner]
    end

    def owner_name
      @page_params[:owner]
    end

    def owner_gravatar_url
      avatar_url_for @user
    end

    def github_url
      if user_page?
        owner_url
      else
        github_url_for @page_params[:projectpath]
      end
    end

    def github_name
      if user_page?
        owner_name
      else
        @page_params[:projectpath]
      end
    end

    # Internal: Whether download links should be shown or not.
    #
    # Returns a boolean.
    def show_downloads?
      !GitHub.enterprise? && !user_page?
    end

    def zip_url
      github_url_for @page_params[:projectpath], "zipball", "master"
    end

    def tar_url
      github_url_for @page_params[:projectpath], "tarball", "master"
    end

    def main_content
      @page_params[:body_html]
    end

    # Internal: <script> tags and JavaScript for Google Analytics.
    #
    # Returns the Google Analytics markup/code if a Google Analytics ID was
    #   provided, or empty string if not.
    def google_analytics
      if @page_params[:google].present?
        <<-END
          <script type="text/javascript">
            var gaJsHost = (("https:" == document.location.protocol) ? "https://ssl." : "http://www.");
            document.write(unescape("%3Cscript src='" + gaJsHost + "google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E"));
          </script>
          <script type="text/javascript">
            try {
              var pageTracker = _gat._getTracker("#{h @page_params[:google]}");
            pageTracker._trackPageview();
            } catch(err) {}
          </script>
        END
      else
        ""
      end
    end

    # Internal: <link>/<script> tags for all the theme's JavaScript/CSS assets
    #
    # Returns a newline-delimited string of tags (can be empty).
    def asset_tags
      [stylesheet_tags, javascript_tags].join "\n"
    end

    # Internal: Whether the page is for a user or not.
    #
    # Returns a boolean.
    def user_page?
      @page_params[:page_type] == "user"
    end

    # Internal: Whether the page is for a project or not.
    #
    # Returns a boolean.
    def project_page?
      @page_params[:page_type] == "project"
    end

    private

    # Internal: Generate a GitHub URL with the specified path.
    #
    # paths - Array of strings representing the GitHub path.
    #
    # Returns a GitHub URL string
    def github_url_for(*paths)
      url = GitHub.ssl? ? "https".dup : "http".dup
      url << "://" << GitHub.host_name
      url << "/"   << paths.join("/")
      url
    end

    # Internal: <link> tags for all the theme's CSS files.
    #
    # Returns a newline-delimited string of tags (can be empty).
    def stylesheet_tags
      @page_params[:stylesheet_paths].map do |path|
        %{<link href="#{path}" media="screen" rel="stylesheet" type="text/css">}
      end.join "\n"
    end

    # Internal: <script> tags for all the theme's JavaScript files.
    #
    # Returns a newline-delimited string of tags (can be empty).
    def javascript_tags
      @page_params[:javascript_paths].map do |path|
        %{<script src="#{path}" type="text/javascript"></script>}
      end.join "\n"
    end
  end
end
