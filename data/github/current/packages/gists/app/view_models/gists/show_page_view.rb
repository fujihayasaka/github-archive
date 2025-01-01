# typed: true
# frozen_string_literal: true

module Gists
  # Controls the gist show view
  # eg https://gist.github.com/defunkt/$GIST_ID
  class ShowPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::TextHelper
    include TextHelper
    include RichwebHelper
    include ForkCountingMethods
    include ApplicationHelper

    attr_reader :gist, :revision, :anonymous_user_is_creator, :files, :cap_view_filter

    delegate :owner, :user_param, :name_with_owner, :parent, :recently_created?,
             :visibility, :stargazer_count, to: :gist

    def page_title
      gist.description.present? ? gist.description : gist.title
    end

    def page_meta_description
      title = gist.title
      description = gist.description
      meta_description = I18n.t("gists.meta_description")
      opengraph_description(title, description, meta_description)
    end

    def gist_viewable?
      !gist.corrupt?
    end

    def show_fork_flag?
      gist.fork? && gist.parent.present?
    end

    def show_edit_link?
      gist_adminable_by_current_user?
    end

    def gist_adminable_by_current_user?
      logged_in? && gist.ui_content_adminable_by?(current_user)
    end

    def show_description?
      gist.description.present?
    end

    def show_delete_link?
      gist_adminable_by_current_user? || anonymous_user_is_creator
    end

    # Public: Returns the passed in files up to the rendered
    # file limit.
    #
    # Returns an Array of TreeEntry objects.
    def files # rubocop:disable Lint/DuplicateMethods
      @limited_files ||= Gist.limit_files(@files, Gist::MAX_FILES)
    end

    # Public: Determines if the passed in files have been truncated
    # due to exceeding the render threshold. If so a notice will
    # be shown to the user.
    #
    # Returns a Boolean.
    def files_limited?
      files.count == Gist::MAX_FILES && @files.count > Gist::MAX_FILES
    end

    # Public: a list of unique file languages included in this gist.
    # If the language cannot be detected 'unknown' will be included.
    #
    # Returns an array of language strings.
    def languages
      @languages ||= files.map do |file|
        file.language ? file.language.to_s.downcase : "unknown"
      end.uniq.sort
    end

    # Public: determines when to show the fork
    # link. Fork link is only hidden if the
    # current user is the owner of the gist.
    #
    # Logged out users will see a fork link
    # but will be directed to login first.
    #
    # Returns a Boolean.
    def show_fork_link?
      return true if !logged_in?

      owner != current_user
    end

    def show_report_abuse_link?
      logged_in? && owner && owner != current_user && !GitHub.enterprise?
    end

    # Generate an HTML formatted gist description.
    #
    # Returns the HTML description.
    def formatted_description
      @formatted_description ||= formatted_gist_description(gist)
    end

    def date_info_text
      recently_created? ? "Created" : "Last active"
    end

    def date_info_date
      recently_created? ? gist.created_at : gist.updated_at
    end

    # Whether this blob refers to a branch.
    #
    # Returns a Boolean.
    def branch?
      false
    end

    # Show this tooltip to users who can't edit this Gist
    #
    # Returns a String
    def cant_edit_tooltip
      if logged_in? && !gist.adminable_by?(current_user)
        "You must be signed in to make or propose changes"
      end
    end

    def embed_script(embed_url)
      script_tag = helpers.content_tag(:script, "", src: embed_url)
      ERB::Util.force_escape(script_tag)
    end

    def tree_name
      revision || gist&.owner&.default_new_repo_branch || "main"
    end
    alias sidebar_tree_name tree_name

    def analytics_tracking_options(flash)
      if flash[:ga_gist_created]
        { "data-ga-load": "Gist, Created, #{analytics_label}" }
      elsif flash[:ga_gist_forked]
        { "data-ga-load": "Gist, Forked, #{analytics_label}" }
      elsif flash[:ga_gist_updated]
        { "data-ga-load": "Gist, Edited, #{analytics_label}" }
      else
        {}
      end
    end

    def analytics_label
      "#{ visibility } #{ gist.anonymous? ? "anonymous" : "owned" }"
    end

    def show_spammy_message?
      gist.spammy? && (logged_in? && current_user.site_admin?)
    end

    def viewer_must_verify_email?
      logged_in? && current_user.must_verify_email?
    end

    def show_social_functions?
      # Since EMUs cannot create or update gists, this should return false for
      # all EMUs and true for every other user
      cap_view_filter && cap_view_filter.authorized?(resource: gist, policy: :emu_ownership)
    end
  end
end
