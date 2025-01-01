# typed: true
# frozen_string_literal: true

module Issues
  class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::UrlHelper
    include EnterpriseManagedUsersHelper
    include Gitkeeper
    include ResilienceHelper

    PULL_REQUESTS = "pull_requests"
    ISSUES = "issues"
    OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER = "first_time_contributor_banner"
    OCTO_CLICK_MAINTAINER_LABEL_EDUCATION_BANNER = "maintainer_label_education"
    OCTO_CLICK_PROJECT_BOARD_ISSUES_BANNER = "project_board_issues"
    GOOGLE_ANALYTICS_DIMENSION_DELIMITER = "; "
    OCTOLYTICS_DIMENSION_DELIMITER = ","

    attr_reader :repo, :query, :pulls_only

    # Is this an unarchived repo with no open issues?
    def new_repo?
      repo && !repo.issues.any? && !repo.archived? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def issues
      attributes[:issues].to_a
    end

    def pinned_issues
      @pinned_issues ||= repo.pinned_issues
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def total_issues_count
      @total_issues_count ||= repo&.issues&.count.to_i
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def title
      name = repo ? repo.name_with_display_owner : "GitHub"
      "#{objects} · #{name}"
    end

    def dashboard_title
      tab_filter_name = attributes[:applied_tab_filter_name]
      if tab_filter_name
        "#{objects} - #{tab_filter_name}"
      else
        objects
      end
    end

    def objects
      pulls_only ? "Pull requests" : "Issues"
    end

    def selected_link
      pulls_only ? :repo_pulls : :repo_issues
    end

    def blankslate_title
      components = Search::Queries::IssueQuery.parse(@query)
      only_two   = components.size == 2

      if new_repo? && pulls_only
        "Welcome to pull requests!"
      elsif new_repo? && repo.has_issues?
        "Welcome to issues!"
      elsif only_two && components.include?([:is, "open"]) && components.include?([:is, "issue"])
        "There aren’t any open issues."
      elsif only_two && components.include?([:is, "open"]) && components.include?([:is, "pr"])
        "There aren’t any open pull requests."
      else
        "No results matched your search."
      end
    end

    def blankslate_copy
      if new_repo?
        if pulls_only
          link = link_to("create a pull request", urls.compare_path(repo, nil))
          helpers.safe_join(["Pull requests help you collaborate on code with other people. As pull requests are created, they’ll appear here in a searchable and filterable list. To get started, you should ", link, "."])
        elsif repo.has_issues?
          link = link_to("create an issue", urls.choose_issue_path(repo.owner, repo))
          helpers.safe_join(["Issues are used to track todos, bugs, feature requests, and more. As issues are created, they’ll appear here in a searchable and filterable list. To get started, you should ", link, "."])
        else
          link = link_to("Check out our guide", "#{GitHub.help_url}/issues/tracking-your-work-with-issues/about-issues")
          helpers.safe_join(["Organize issues and pull requests by using labels and milestones to see results here. ", link, " on mastering issues."])
        end
      else
        all_link = link_to("all of GitHub", urls.search_path)
        advanced_link = link_to("advanced search", urls.advanced_search_path)
        helpers.safe_join(["You could search ", all_link, " or try an ", advanced_link, "."])
      end
    end

    def blankslate_icon
      if pulls_only
        "git-pull-request"
      else
        "issue-opened"
      end
    end

    def query_error_title
      "Oops!"
    end

    def query_error_copy
      docs = link_to("the docs", "#{GitHub.help_url}/articles/searching-issues")
      helpers.safe_join(["Sorry, we couldn’t parse your query. Have you looked at ", docs, "?"])
    end

    def query_error_icon
      "alert"
    end

    def instrument_ftc_banner_view(is_pull_requests:)
      key = is_pull_requests ? PULL_REQUESTS : ISSUES

      GitHub.instrument("#{key}.first_time_contributor_banner", dimensions: {
        view: key,
        banner_shows_all_issues: key == ISSUES ? false : repo.has_issues?,
        banner_shows_contributing_guide: repo_has_contributing?,
        banner_shows_open_source_guide: !repo_has_contributing?,
        banner_shows_labels: key == PULL_REQUESTS ? false : display_labels?,
        label_name: nil,
        action: "view",
        actor_id: current_user.id,
        user_id: repo.owner.id,
        repository_id: repo.id,
      })
    end

    # The path to submit data to for an issues search.
    #
    # Returns a String.
    def target_path(options = {})
      urls.issues_path(repo.owner, repo, options)
    end

    def repo_help_wanted_label
      return @repo_help_wanted_label if defined?(@repo_help_wanted_label)
      @repo_help_wanted_label = repo.help_wanted_label
    end

    def repo_good_first_issue_label
      return @repo_good_first_issue_label if defined?(@repo_good_first_issue_label)
      @repo_good_first_issue_label = repo.good_first_issue_label
    end

    def display_labels?
      return @display_labels if defined?(@display_labels)
      @display_labels = display_help_wanted_label? || display_good_first_issue_label?
    end

    def display_help_wanted_label?
      return @display_help_wanted_label if defined?(@display_help_wanted_label)
      @display_help_wanted_label = repo_has_help_wanted_issues? && repo_help_wanted_label.present?
    end

    def display_good_first_issue_label?
      return @display_good_first_issue_label if defined?(@display_good_first_issue_label)
      @display_good_first_issue_label = repo_has_good_first_issue_issues? && repo_good_first_issue_label.present?
    end

    def display_help_wanted_and_good_first_issue_labels?
      display_help_wanted_label? && display_good_first_issue_label?
    end

    # Private:
    #
    # Returns Boolean
    def repo_has_help_wanted_issues?
      community_profile.present? && community_profile.help_wanted_issues_count > 0
    end

    # Private
    #
    # Returns Boolean
    def repo_has_good_first_issue_issues?
      community_profile.present? && community_profile.good_first_issue_issues_count > 0
    end

    # Public: Returns true unless the repo has both 'help wanted' and 'good first issue' labels
    #
    # Returns a Boolean.
    def show_maintainer_label_education_banner_cta?
      if repo_help_wanted_label && repo_good_first_issue_label
        return false
      end
      true
    end

    # Public: Returns true if the viewer should see a 'first-time contributor' banner.
    #
    # is_pull_requests - Boolean indicating whether the user is on the /pulls/ page or /issues/
    #
    # Returns a Boolean.
    def show_first_time_contributor_banner?(is_pull_requests:)
      return @show_first_time_contributor_banner if defined?(@show_first_time_contributor_banner)

      notice_subject = is_pull_requests ? "pull_requests" : "issues"
      notice = "first_time_contributor_#{notice_subject}_banner"

      @show_first_time_contributor_banner = repo.public? &&
        !repo.fork? &&
        !repo.archived? &&
        !GitHub.enterprise? &&
        logged_in? &&
        !repo.owner.spammy? &&
        repo.owner_id != current_user.id &&
        !repo.adminable_by?(current_user) &&
        !current_user.dismissed_repository_notice?(notice, repository_id: repo.id) &&
        !current_user.dismissed_notice?(notice) &&
        !viewer_has_contributed?(is_pull_requests: is_pull_requests) &&
        !repo.owner_blocking?(current_user) &&
        !contribution_disabled_for_emu?
    end

    # Public: Returns true if the current viewer has made any contributions ever on GitHub.
    #
    # Returns a Boolean.
    def user_has_any_contributions?
      return @user_has_any_contributions if defined?(@user_has_any_contributions)
      @user_has_any_contributions = logged_in? && current_user.any_contributions_ever?
    end

    # Public: Returns true if the current viewer has opened any pull requests on GitHub.
    #
    # Returns a Boolean.
    def user_has_any_pull_requests?
      return @user_has_any_pull_requests if defined? @user_has_any_pull_requests
      @user_has_any_pull_requests = logged_in? && current_user.pull_requests.exists?
    end

    # Public: Returns a string URL to learn more about pull requests.
    def pull_request_help_url
      DocsUrlConfig.url_for("pull-requests/about-pull-requests")
    end

    # Returns true if the repository has a contributing file
    #
    # Returns a Boolean
    def repo_has_contributing?
      with_database_error_fallback(fallback: false) do
        repo.preferred_files.exists?(:contributing)
      end
    end

    # Returns the relative path to a repository's contributing file
    #
    # Returns a String
    def contributing_guidelines_path
      return unless repo_has_contributing?
      repo.preferred_files.fetch(:contributing).permalink
    end

    def open_source_guide_url
      "https://opensource.guide"
    end

    # Public: Returns a Hash of analytics tracking data attributes for the link
    # to all of the repo's issues
    def first_time_contributor_banner_data_attributes_click_all_issues
      shared_dimensions = [
        "view:#{PULL_REQUESTS}",
        "banner_shows_all_issues:true",
        "banner_shows_contributing_guide:#{repo_has_contributing?}",
        "banner_shows_open_source_guide:#{!repo_has_contributing?}",
        "banner_shows_labels:false",
        "label_name:nil",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "First-time contributor banner, all issues, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_all_issues").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    # Public: Returns a Hash of analytics tracking data attributes for the link
    # to the repo's contributing guidelines
    def first_time_contributor_banner_data_attributes_click_contributing(
      view:,
      banner_shows_all_issues:,
      banner_shows_open_source_guide:,
      banner_shows_labels:
    )
      shared_dimensions = [
        "view:#{view}",
        "banner_shows_all_issues:#{banner_shows_all_issues}",
        "banner_shows_contributing_guide:true",
        "banner_shows_open_source_guide:#{banner_shows_open_source_guide}",
        "banner_shows_labels:#{banner_shows_labels}",
        "label_name:nil",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)
      {
        "ga-click" => "First-time contributor banner, contributing, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_contributing").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    # Public: Returns a Hash of analytics tracking data attributes for the link
    # to the repo's 'help' URL
    def first_time_contributor_banner_data_attributes_click_help
      shared_dimensions = [
        "view:#{PULL_REQUESTS}",
        "banner_shows_all_issues:#{repo.has_issues?}",
        "banner_shows_contributing_guide:#{repo_has_contributing?}",
        "banner_shows_open_source_guide:false",
        "banner_shows_labels:false",
        "label_name:nil",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "First-time contributor banner, help, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_help").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    # Public: Returns a Hash of analytics tracking data attributes for the link
    # to learn more
    def first_time_contributor_banner_data_attributes_click_learn_more
      shared_dimensions = [
        "view:#{PULL_REQUESTS}",
        "banner_shows_all_issues:#{repo.has_issues?}",
        "banner_shows_contributing_guide:#{repo_has_contributing?}",
        "banner_shows_open_source_guide:false",
        "banner_shows_labels:false",
        "label_name:nil",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "First-time contributor banner, learn more, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_learn_more").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    # Public: Returns a Hash of analytics tracking data attributes for the link
    # to the Open Source Guide
    def first_time_contributor_banner_data_attributes_click_open_source_guide
      shared_dimensions = [
        "view:issues",
        "banner_shows_all_issues:false",
        "banner_shows_contributing_guide:false",
        "banner_shows_open_source_guide:true",
        "banner_shows_labels:#{display_labels?}",
        "label_name:nil",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "First-time contributor banner, open source guide, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_open_source_guide").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    # Public: Returns a Hash of analytics tracking data attributes for the link
    # to the repo's issues with the given label
    def first_time_contributor_banner_data_attributes_click_labeled_issues(label_name:)
      shared_dimensions = [
        "view:#{ISSUES}",
        "label_name:#{label_name}",
        "banner_shows_all_issues:false",
        "banner_shows_contributing_guide:#{repo_has_contributing?}",
        "banner_shows_open_source_guide:#{!repo_has_contributing?}",
        "banner_shows_labels:true",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "First-time contributor banner, labeled issues, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_labeled_issues").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    # Public: Returns a Hash of analytics tracking data attributes for the
    # dismiss button
    def first_time_contributor_banner_data_attributes_click_dismiss(
      view:,
      banner_shows_all_issues:,
      banner_shows_labels:,
      dismiss_length:
    )
      shared_dimensions = [
        "view:#{view}",
        "banner_shows_all_issues:#{banner_shows_all_issues}",
        "banner_shows_contributing_guide:#{repo_has_contributing?}",
        "banner_shows_open_source_guide:#{!repo_has_contributing?}",
        "banner_shows_labels:#{banner_shows_labels}",
        "label_name:nil",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "First-time contributor banner, dismiss #{dismiss_length}, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_FIRST_TIME_CONTRIBUTOR_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_dismiss").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    def instrument_maintainer_label_education_banner
      GitHub.instrument("repo.maintainer_label_education", {
        dimensions: {
          object: "banner",
          action: "view",
          actor_id: current_user.id,
          user_id: repo.owner_id,
          repository_nwo: repo.name_with_display_owner,
          repository_id: repo.id,
          public: repo.public?,
          context: "issues",
        },
      })
    end

    def maintainer_label_education_banner_data_attributes_click_dismiss
      shared_dimensions = [
        "repository_nwo:#{repo.name_with_display_owner}",
        "context:issues",
        "public:#{repo.public?}",
        "repo_has_help_wanted_label:#{repo_help_wanted_label.present?}",
        "repo_has_good_first_issue_label:#{repo_good_first_issue_label.present?}",
        "shows_go_to_labels:#{show_maintainer_label_education_banner_cta?}",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "Maintainer label education banner, dismiss, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_MAINTAINER_LABEL_EDUCATION_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_dismiss").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    def maintainer_label_education_banner_data_attributes_click_go_to_labels
      shared_dimensions = [
        "repository_nwo:#{repo.name_with_display_owner}",
        "context:issues",
        "label_name:nil",
        "public:#{repo.public?}",
        "repo_has_help_wanted_label:#{repo_help_wanted_label.present?}",
        "repo_has_good_first_issue_label:#{repo_good_first_issue_label.present?}",
        "shows_go_to_labels:true",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "Maintainer label education banner, dismiss, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_MAINTAINER_LABEL_EDUCATION_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_go_to_labels").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    def maintainer_label_education_banner_data_attributes_click_label(label_name:)
      shared_dimensions = [
        "repository_nwo:#{repo.name_with_display_owner}",
        "context:issues",
        "label_name:#{label_name}",
        "public:#{repo.public?}",
        "repo_has_help_wanted_label:#{repo_help_wanted_label.present?}",
        "repo_has_good_first_issue_label:#{repo_good_first_issue_label.present?}",
        "shows_go_to_labels:#{show_maintainer_label_education_banner_cta?}",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "Maintainer label education banner, dismiss, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_MAINTAINER_LABEL_EDUCATION_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: "click_label").
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    def project_board_issues_banner_data_attributes(action:)
      actions = %w[dismiss click]
      return unless actions.include?(action)

      shared_dimensions = [
        "repository_nwo:#{repo.name_with_display_owner}",
        "context:issues",
      ]
      google_analytics_dimensions = shared_dimensions.join(GOOGLE_ANALYTICS_DIMENSION_DELIMITER)

      {
        "ga-click" => "Project board issues banner, dismiss, #{google_analytics_dimensions}",
        "octo-click" => OCTO_CLICK_PROJECT_BOARD_ISSUES_BANNER,
        "octo-dimensions" => octolytics_dimensions(action: action).
          concat(shared_dimensions).
          join(OCTOLYTICS_DIMENSION_DELIMITER),
      }
    end

    def display_recently_touched_branches_list?
      # Protect ourselves against a Spokes DB cluster outage, which would impact
      # the `repo.empty?` call. To be safe, if we hit any DB error we can skip
      # this banner.
      with_database_error_fallback(fallback: false) do
        pulls_only && logged_in? && !(repo.empty? || repo.locked?) && !is_stacks_config_in_progress?(repo)
      end
    end

    private

    def octolytics_dimensions(action:)
      [
        "action:#{action}",
        "actor_id:#{current_user.id}",
        "user_id:#{repo.owner.id}",
        "repository_id:#{repo.id}",
      ]
    end

    # Private: Returns true if the current user has contributed to the repository in a way relevant
    # to the page they're currently on.
    #
    # is_pull_requests - Boolean indicating whether the user is on the /pulls/ page or /issues/
    #
    # Returns a Boolean.
    def viewer_has_contributed?(is_pull_requests:)
      return true if repo.contributor?(current_user, type: CommitContribution)

      if is_pull_requests
        repo.contributor?(current_user, type: PullRequest)
      else
        repo.contributor?(current_user, type: Issue)
      end
    end

    def community_profile
      @community_profile ||= repo.community_profile
    end

    # Private: Returns true if the current repository is outside of an
    # Enterprise Managed User's Enterprise.
    def contribution_disabled_for_emu?
      !attributes[:cap_view_filter].authorized?(resource: repo, policy: :emu_ownership)
    end
  end
end
