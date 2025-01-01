# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileAppElement < Platform::Enums::Base
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different mobile elements."

      # Misc
      value "VIEWER_PULL_TO_REFRESH", "The viewer has initiated a pull to refresh gesture", value: "viewer_pull_to_refresh"

      # Discussions
      value "REPOSITORY_DISCUSSIONS_LIST_FILTER", "A filter on the list of discussions related to the repository", value: "repository_discussions_list_filter"
      value "VIEWER_DISCUSSIONS_LIST_FILTER", "A filter on the list of discussions related to the viewer", value: "viewer_discussions_list_filter"

      # Account switcher
      value "ACCOUNT_SWITCHER_ADD", "Account switcher button to add a new account", value: "account_switcher_add"
      value "ACCOUNT_SWITCHER_ITEM", "A user account in the user account switcher", value: "account_switcher_item"
      value "ACCOUNT_SWITCHER_REMOVE", "Account switcher button to remove a logged in account", value: "account_switcher_remove"

      # Deep links
      value "DEEP_LINK_ERROR_ACCOUNT_SWITCHER", "The account switcher button in the deep link error screen", value: "deep_link_error_account_switcher"

      # Explore
      value "EXPLORE_BOTTOM_NAVIGATION", "Explore button in the bottom navigation", value: "explore_bottom_navigation"
      value "EXPLORE_TRENDING_REPOSITORY", "A trending repository on explore", value: "explore_trending_repository"
      value "EXPLORE_FOR_YOU_REPOSITORY", "A for you repository on explore", value: "explore_for_you_repository"
      value "EXPLORE_FEATURED_REPOSITORY", "A featured repository on explore", value: "explore_featured_repository"
      value "EXPLORE_STAR_TRENDING_REPOSITORY", "A trending repository star button on explore", value: "explore_star_trending_repository"
      value "EXPLORE_STAR_FOR_YOU_REPOSITORY", "A for you repository star button on explore", value: "explore_star_for_you_repository"
      value "EXPLORE_STAR_FEATURED_REPOSITORY", "A featured repository star button on explore", value: "explore_star_featured_repository"
      value "EXPLORE_TRENDING_LIST_FILTER", "Trending list filter bar on explore", "value": "explore_trending_list_filter"
      value "STAR_REPOSITORY", "A repository star button", value: "star_repository"
      value "SHOW_MORE_ROLLUP", "Show more button on a rollup", value: "show_more_rollup"

      # Follows
      value "FOLLOW", "A follow button", value: "follow"

      # Home
      value "HOME_BOTTOM_NAVIGATION", "Home button in the bottom navigation", value: "home_bottom_navigation"
      value "HOME_FAVORITE_REPOSITORY_ITEM", "An item in the Favorites list in Home", value: "home_favorite_repository_item"
      value "HOME_ISSUES", "Global list of issues for a user on home", value: "home_issues"
      value "HOME_PULL_REQUESTS", "Global list of pull requests for a user on home", value: "home_pull_requests"
      value "HOME_REPOSITORIES", "Global list of repositories for a user on home", value: "home_repositories"
      value "HOME_ORGANIZATIONS", "Global list of organizations for a user on home", value: "home_organizations"
      value "HOME_CREATE_ISSUE", "Create issue button on home", value: "home_create_issue"
      value "HOME_RECENT_ACTIVITY_ITEM", "An item in the Recent activity list in Home", value: "home_recent_activity_item"
      value "HOME_RELEASE_NOTES", "Release notes banner on home", value: "home_release_notes"
      value "HOME_DISCUSSIONS", "Global list of discussions for a user on home", value: "home_discussions"
      value "HOME_STARRED", "Global list of starred repositories for a user on home", value: "home_starred"
      value "HOME_SHORTCUTS", "Global list of shortcuts for a user on home", value: "home_shortcuts"
      value "HOME_PROJECTS", "Global list of projects for a user on home", value: "home_projects"
      value "HOME_IN_APP_UPDATE", "In-app update banner on home", value: "home_in_app_update"

      # Notifications
      value "NOTIFICATION_LIST", "The list of notifications a user has i.e. inbox list", value: "notification_list"
      value "NOTIFICATION_LIST_ITEM", "A list item in the notification list.", value: "notification_list_item"
      value "NOTIFICATION_LIST_ITEM_FOCUSED", "A list item in the notification list while the focused filter is enabled.", value: "notification_list_item_focused"
      value "NOTIFICATION_LIST_ITEM_UNDO", "Undo button when a notification is swiped.", value: "notification_list_item_undo"
      value "NOTIFICATION_LIST_FILTER", "A filter on the list of notifications", value: "notification_list_filter"
      value "NOTIFICATION_FILTER", "Filter button on notification screen.", value: "notification_filter"
      value "NOTIFICATION_BOTTOM_NAVIGATION", "Notification button in the bottom navigation.", value: "notification_bottom_navigation"
      value "NOTIFICATION_PUSH", "A push notification sent to a device.", value: "notification_push"
      value "PUSH_NOTIFICATIONS_PERMISSION_DIALOG_ALLOW", "The allow button on the push notification permission request", value: "push_notifications_permission_dialog_allow"
      value "PUSH_NOTIFICATIONS_PERMISSION_DIALOG_DENY", "The deny button on the push notification permission request", value: "push_notifications_permission_dialog_deny"

      # Notifications Onboarding
      value "NOTIFICATION_ONBOARDING_NUX_BANNER", "The NUX banner of notifications onboarding", value: "notification_onboarding_nux_banner"
      value "NOTIFICATION_ONBOARDING_MISSING_OUT_BANNER", "The missing out banner of notifications which appears after users have disabled notifications", value: "notification_onboarding_missing_out_banner"
      value "NOTIFICATION_ONBOARDING_CONTINUE_BANNER", "The continue banner on notifications onboarding which appears if a user dismisses push notification setup prior to completion", value: "notification_onboarding_continue_banner"
      value "NOTIFICATION_ONBOARDING_REVIEW_BANNER", "The review banner which asks users to review their notifications preferences", value: "notification_onboarding_review_banner"
      value "NOTIFICATION_ONBOARDING_REVIEW_CHANGE_SETTINGS", "Tracks whether or not existing users change any settings at all when reviewing their preferences", value: "notification_onboarding_review_change_settings"
      value "NOTIFICATION_ONBOARDING_PROGRESS_REVIEW", "The notifications onboarding progress through the flow for users reviewing their notifications", value: "notification_onboarding_progress_review"
      value "NOTIFICATION_ONBOARDING_PROGRESS", "The notifications onboarding progress through the flow for users setting up their notifications", value: "notification_onboarding_progress"
      value "NOTIFICATION_ONBOARDING_RECAPTURE", "A user who has re-enabled notifications after having them disabled", value: "notification_onboarding_recapture"
      value "NOTIFICATION_ONBOARDING_EXPIRED_TWO_FACTOR_BANNER", "The banner to indicate that there are expired two factor notifications which appears after users have disabled notifications and have expired auth requests", value: "notification_onboarding_expired_two_factor_banner"

      # Focused Notifications
      value "FOCUS_CTA_VIEWED", "Used when the focused notification filter explainer sheet is shown to users", value: "focus_cta_viewed"
      value "FOCUS_CTA_DISMISSED", "Used when the focused notification filter explainer sheet is dismissed without enabling the filter", value: "focus_cta_dismissed"
      value "FOCUS_CTA_ENABLED", "Used when the focused notification filter explainer sheet is dismissed via enabling the filter", value: "focus_cta_enabled"

      # Issues
      value "ISSUES_LIST_ITEM", "A list item in the issues list.", value: "issues_list_item"
      value "VIEWER_ISSUES_LIST_FILTER", "A filter on the list of issues related to the user.", value: "viewer_issues_list_filter"
      value "REPOSITORY_ISSUES_LIST_FILTER", "A filter on the list of issues related to the repository.", value: "repository_issues_list_filter"
      value "ISSUE_COMPOSER", "The issue composer.", value: "issue_composer"
      value "ISSUE_COMPOSER_PROPERTY_BAR", "The issue composer property bar.", value: "issue_composer_property_bar"
      value "ISSUES_SEARCH", "The issues search bar.", value: "issues_search"
      value "HOME_ISSUES_LIST_NEW_ISSUE", "Create new issue from Home Issues list.", value: "home_issues_list_new_issue"


      # Profile
      value "PROFILE_BOTTOM_NAVIGATION", "Profile button in the bottom navigation", value: "profile_bottom_navigation"
      value "PROFILE_HEADER_NAME", "Profile header user name", value: "profile_header_name"

      # Projects
      value "PROJECTS_LIST_ITEM", "A list item in the projects list.", value: "projects_list_item"
      value "PROJECTS_TABLE_VIEW_LIST_ITEM", "A list item in the table view of a project.", value: "projects_table_view_list_item"
      value "PROJECTS_QUICK_ACTION_OPEN_DETAILS", "Open details of an item in a project", value: "projects_quick_action_open_details"
      value "PROJECTS_QUICK_ACTION_EDIT_FIELD", "The edit field quick action for an item in a project", value: "projects_quick_action_edit_field"
      value "PROJECTS_QUICK_ACTION_EDIT_TITLE", "The edit title quick action for an item in a project", value: "projects_quick_action_edit_title"
      value "PROJECTS_QUICK_ACTION_CLOSE", "The close quick action for an item in a project", value: "projects_quick_action_close"
      value "PROJECTS_QUICK_ACTION_REOPEN", "The re-open quick action for an item in a project", value: "projects_quick_action_reopen"
      value "PROJECTS_QUICK_ACTION_DELETE", "The delete quick action for an item in a project", value: "projects_quick_action_delete"
      value "PROJECTS_QUICK_ACTION_OTHER_PROJECTS", "The other projects quick action for an item in a project", value: "projects_quick_action_other"
      value "PROJECT_VIEW", "The project view", value: "project_view"
      value "PROJECT_VIEW_TIMEOUT_CTA", "The CTA displayed when the API responds with a timeout loading a project view", value: "project_view_timeout_cta"

      # Pull Requests
      value "PULL_REQUESTS_LIST_ITEM", "A list item in the pull requests list.", value: "pull_requests_list_item"
      value "VIEWER_PULL_REQUESTS_LIST_FILTER", "A filter on the list of pull requests related to the user.", value: "viewer_pull_requests_list_filter"
      value "REPOSITORY_PULL_REQUESTS_LIST_FILTER", "A filter on the list of pull requests related to the repository.", value: "repository_pull_requests_list_filter"
      value "PULL_REQUESTS_SEARCH", "The pull requests search bar.", value: "pull_requests_search"
      value "PULL_REQUEST_REVIEW_BANNER", "The banner to review a pull request.", value: "pull_request_review_banner"
      value "PULL_REQUEST_REVIEW_CTA", "The CTA to review a pull request in the Reviews section.", value: "pull_request_review_cta"
      value "PULL_REQUEST_FILES_CHANGED", "The files changed entry point in a pull request.", value: "pull_request_files_changed"

      # Files changed
      value "FINISH_REVIEW_BOA", "The finish review BoA button in the Files changed screen.", value: "finish_review_boa"

      # Submit review
      value "SUBMIT_REVIEW", "The submit review button in the Submit review screen.", value: "submit_review"

      # Triage Sheet
      value "TRIAGE_EXPAND", "Triage sheet.", value: "triage_expand"
      value "TRIAGE_COMMENT", "Triage sheet comment button.", value: "triage_comment"
      value "TRIAGE_COMMENT_UP", "Triage sheet comment up button.", value: "triage_comment_up"
      value "TRIAGE_COMMENT_DOWN", "Triage sheet comment down button.", value: "triage_comment_down"
      value "TRIAGE_COMMENT_EDIT", "Triage sheet comment edit.", value: "triage_comment_edit"
      value "TRIAGE_REVIEW_REQUEST_EDIT", "Triage sheet review request edit.", value: "triage_review_request_edit"
      value "TRIAGE_ASSIGNEE_EDIT", "Triage sheet assignee edit.", value: "triage_assignee_edit"
      value "TRIAGE_LABEL_EDIT", "Triage sheet label edit.", value: "triage_label_edit"
      value "TRIAGE_LINKED_ITEM_EDIT", "Triage sheet linked item edit.", value: "triage_linked_item_edit"
      value "TRIAGE_ISSUE_TYPE_EDIT", "Triage sheet issue type edit.", value: "triage_issue_type_edit"
      value "TRIAGE_PROJECT_EDIT", "Triage sheet project edit.", value: "triage_project_edit"
      value "TRIAGE_PROJECT_NEXT_EDIT", "Triage sheet project next edit.", value: "triage_project_next_edit"
      value "TRIAGE_PROJECT_NEXT_PICKER_RECENT", "Triage sheet project next recent tab picker.", value: "triage_project_next_pick_recent"
      value "TRIAGE_PROJECT_NEXT_PICKER_OWNER", "Triage sheet project next owner tab picker.", value: "triage_project_next_pick_owner"
      value "TRIAGE_MILESTONE_EDIT", "Triage sheet milestone edit.", value: "triage_milestone_edit"
      value "TRIAGE_CLOSE", "Triage sheet close button.", value: "triage_close"
      value "TRIAGE_LOCK", "Triage sheet lock button.", value: "triage_lock"
      value "TRIAGE_UNSUBSCRIBE", "Triage sheet unsubscribe button.", value: "triage_unsubscribe"

      # Onboarding banner
      value "ONBOARDING_BANNER", "Legacy push notifications onboarding banner.", value: "onboarding_banner"
      value "NOTIFICATIONS_ONBOARDING_BANNER", "Notifications onboarding banner, including configuring push notifications, swipe settings and push schedules.", value: "notifications_onboarding_banner"

      # Shortcuts
      value "SHORTCUTS_LIST_ITEM", "A list item in the shortcuts list.", value: "shortcuts_list_item"
      value "SHORTCUT_SUGGESTIONS_LIST_ITEM", "A list item in the shortcut suggestions list.", value: "shortcut_suggestion_list_item"

      # Releases
      value "REPOSITORY_LATEST_RELEASE", "A latest release on a repository.", value: "repository_latest_release"
      value "RELEASES_LIST_LATEST_RELEASE", "A latest release on a list of releases.", value: "releases_list_latest_release"
      value "RELEASE_DOWNLOAD_ASSET", "Release asset download button.", value: "release_download_asset"
      value "RELEASE_LINKED_DISCUSSION", "A linked discussion to a release.", value: "release_linked_discussion"

      # Repository
      value "PROFILE_REPOSITORY_LIST_FILTER", "A filter on the list of repositories related to the user or the organization", value: "user_repository_list_filter"
      value "HOME_REPOSITORY_LIST_FILTER", "A filter on the ranked list of repositories related to the viewer.", value: "home_repository_list_filter"
      value "REPOSITORY_EDIT_README", "Edit readme file button.", value: "repository_edit_readme"
      value "PIN_SHORTCUT", "Menu option to pin a shortcut.", value: "pin_shortcut"

      # Settings
      value "SETTINGS_DISABLE_ANALYTICS", "Option to disable sending analytics data", value: "settings_disable_analytics"
      value "SETTINGS_ACCOUNTS", "Option to open the account switcher in Settings", value: "settings_accounts"
      value "SETTINGS_ENABLE_APP_LOCK", "Option to enable app lock in Settings", value: "settings_enable_app_lock"

      # Multi account
      value "VIEWING_AS_TOAST", "The toast notification displayed after opening a link when more than one account can open a link", value: "viewing_as_toast"

      # Search
      value "GLOBAL_SEARCH_SHORTCUT", "A shortcut in global search when there is a search query", value: "global_search_shortcut"
      value "CODE_SEARCH_LIST_ITEM", "A list item in the code search list", value: "code_search_list_item"

      #Copilot
      value "COPILOT_CHAT_BUTTON", "A button to launch Copilot", value: "copilot_chat_button"
      value "COPILOT_CHAT_MESSAGE_COPY", "A button to copy Copilot message ", value: "copilot_chat_message_copy"
      value "COPILOT_CHAT_CONVERSATION", "A button to open an existing Copilot conversation", value: "copilot_chat_conversation"
      value "COPILOT_CHAT_SUGGESTION", "A button to send a suggested message to Copilot", value: "copilot_chat_suggestion"
      value "COPILOT_DELETE_CONVERSATION", "A button to delete a Copilot Chat conversation", value: "copilot_delete_conversation"
      value "COPILOT_NEW_CONVERSATION", "A button to create a new Copilot Chat conversation", value: "copilot_new_conversation"
      value "COPILOT_RECENT_CONVERSATION", "A button to switch to a recent Copilot Chat conversation in the dropdown menu", value: "copilot_recent_conversation"
      value "COPILOT_ALL_CONVERSATIONS", "A button to view all Copilot Chat conversations", value: "copilot_all_conversations"
      value "COPILOT_SCOPE_LINK", "A link to switch the Copilot Chat scope", value: "copilot_scope_link"
      value "COPILOT_BUY", "A button to buy a Copilot Individual license via IAP", value: "copilot_buy"
      value "COPILOT_DISMISS_PAYWALL", "A button to dismiss the Copilot paywall sheet ", value: "copilot_dismiss_paywall"
      value "COPILOT_RESTORE_PURCHASE", "A button to restore an existing Copilot license", value: "copilot_restore_purchase"
      value "COPILOT_MANAGE_SUBSCRIPTION", "A button to manage an existing Copilot Individual IAP subscription", value: "copilot_manage_subscription"
      value "COPILOT_PRIVACY_POLICY", "A button to view the Copilot privacy policy", value: "copilot_privacy_policy"
      value "COPILOT_AGREEMENT", "A button to view the Copilot customer agreement", value: "copilot_agreement"
      value "COPILOT_SETTINGS_ENABLE", "A toggle to enable Copilot Chat on a device", value: "copilot_settings_enable"
      value "COPILOT_SETTINGS_HIDE_BOA", "A toggle to hide the Copilot Bar of Actions", value: "copilot_settings_hide_boa"
      value "COPILOT_POLICY_DISABLED_LINK", "A link to learn more about a disabled mobile chat policy", value: "copilot_policy_disabled_link"
      value "COPILOT_LEARN_MORE", "A link to learn more about Copilot", value: "copilot_learn_more"
      value "COPILOT_UPSELL_LEARN_MORE", "A button to launch the Copilot upsell learn more sheet", value: "copilot_upsell_learn_more"
      value "COPILOT_UPSELL_DISMISS", "A button to dismiss the Copilot upsell sheet", value: "copilot_upsell_dismiss"

      # Compare branches and create a pull request
      value "COMPARE_BRANCHES", "A button to open the compare branches screen", value: "compare_branches"
      value "COMPARE_BRANCHES_FILES_CHANGED", "A button to open the files changed screen from the compare branches screen", value: "compare_branches_files_changed"
      value "COMPARE_BRANCHES_COMMITS", "A button to open the commits screen from the compare branches screen", value: "compare_branches_commits"
      value "COMPARE_BRANCHES_ACTIVE_PULL_REQUEST", "A button to open the active pull request screen from the compare branches screen", value: "compare_branches_active_pull_request"
      value "COMPARE_BRANCHES_CREATE_PULL_REQUEST", "A button to create a pull request from the compare branches screen", value: "compare_branches_create_pull_request"
      value "PULL_REQUEST_COMPOSER_SUBMIT", "A button to create a pull request from the pull request composer", value: "pull_request_composer_submit"
      value "PULL_REQUEST_LEGACY_CREATION_SUBMIT", "A button to create a pull request from the legacy pull request creation screen", value: "pull_request_legacy_creation_submit"

      # Sub-issues
      value "SUB_ISSUE_SECTION", "A button that toggles the visibility of sub-issues in the issues screen", value: "sub_issue_section"
      value "SUB_ISSUE_NESTED_ISSUES_TOGGLE", "A button that toggles the visibility of nested sub-issues", value: "sub_issue_nested_issues_toggle"
      value "SUB_ISSUE_ISSUE", "A button that taps through to the issue detail from a sub-issue", value: "sub_issue_issue"
      value "SUB_ISSUE_ADD_EXISTING_ISSUE", "A button that opens a screen adds an existing issue as a sub-issue to the current issue", value: "sub_issue_add_existing_issue"
      value "SUB_ISSUE_ADD_NEW_ISSUE", "A button that opens a screen to add a new issue as a sub-issue to the current issue", value: "sub_issue_add_new_issue"
      value "SUB_ISSUE_EDIT_SUB_ISSUE", "A button that opens a screen that edits/removes a sub-issue", value: "sub_issue_edit_sub_issue"
      value "SUB_ISSUE_EDIT_PARENT_ISSUE", "A button that opens a screen that edits/removes a parent issue", value: "sub_issue_edit_parent_issue"
      value "SUB_ISSUE_PARENT_ISSUE", "A button that taps through to the issue detail from a parent issue", value: "sub_issue_parent_issue"
    end
  end
end
