# typed: true
# frozen_string_literal: true

class FgpMetadata
  attr_reader :label, :category, :description

  # Fine Grained Permission metadata
  def initialize(fgp)
    @label = fgp
    @category = FgpMetadata.category_for(fgp)
    @description = FgpMetadata.description_for(fgp)
  end

  # FGP contains the metadata for an individual fine grained permission
  def self.for(fgp)
    new(fgp.to_sym)
  end

  # Public: get all the categories and FGPs for a role
  #
  # - role: the Role object
  #
  # Returns a Hash of categories titles to FGP descriptions
  def self.for_role(role)
    perms = role.permissions.map(&:action)

    CATEGORIES.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(category, permissions), result|
      permissions.each do |category_permission|
        if perms.include?(category_permission.to_s)
          result[title_for(category)] << description_for(category_permission)
        end
      end
    end
  end

  def self.categories
    CATEGORIES.keys
  end

  def self.category_for(fgp)
    CATEGORIES.each do |category, fgps|
      return category if fgps.include?(fgp)
    end

    :unknown
  end

  def self.description_for(fgp)
    DESCRIPTIONS[fgp] || "unknown"
  end

  # Public: the human readable title for every FGP category
  def self.title_for(category)
    case category
    when :issues
      "Issue"
    when :prs
      "Pull Request"
    when :issues_prs
      "Issue and Pull Request"
    when :repository
      "Repository"
    when :security
      "Security"
    when :discussions
      "Discussions"
    when :merge_queue
      "Merge Queue"
    end
  end

  # Public: the octicon for every FGP category
  def self.icon_for(category)
    case category
    when :issues
      "issue-opened"
    when :prs
      "git-pull-request"
    when :issues_prs
      "file-diff"
    when :repository
      "repo"
    when :security
      "shield"
    when :discussions
      "comment-discussion"
    when :merge_queue
      "git-merge-queue"
    end
  end

  # Public: the octicon for every FGP category by title
  def self.icon_for_title(title)
    case title
    when "Issue"
      "issue-opened"
    when "Pull Request"
      "git-pull-request"
    when "Issue and Pull Request"
      "file-diff"
    when "Repository"
      "repo"
    when "Security"
      "shield"
    when "Discussions"
      "comment-discussion"
    when "Merge Queue"
      "git-merge-queue"
    end
  end

  DESCRIPTIONS = {
    add_assignee:                       "Assign or remove a user",
    remove_assignee:                    "Remove an assigned user",
    add_label:                          "Add or remove a label",
    remove_label:                       "Remove a label",
    close_issue:                        "Close an issue",
    reopen_issue:                       "Reopen a closed issue",
    delete_issue:                       "Delete an issue",
    mark_as_duplicate:                  "Mark an issue as a duplicate",
    close_pull_request:                 "Close a pull request",
    reopen_pull_request:                "Reopen a closed pull request",
    request_pr_review:                  "Request a pull request review",
    manage_settings_merge_types:        "Manage pull request merging settings",
    manage_settings_pages:              "Manage GitHub Page settings",
    manage_settings_projects:           "Manage project settings",
    manage_settings_wiki:               "Manage wiki settings",
    manage_topics:                      "Manage topics",
    manage_deploy_keys:                 "Manage deploy keys",
    manage_webhooks:                    "Manage webhooks",
    push_protected_branch:              "Push commits to protected branches",
    set_interaction_limits:             "Set interaction limits",
    set_milestone:                      "Set milestones",
    set_issue_type:                     "Set an issue type",
    set_social_preview:                 "Set the social preview",
    edit_repo_metadata:                 "Edit repository metadata",
    read_code_scanning:                 "View code scanning alerts",
    write_code_scanning:                "Dismiss or reopen code scanning alerts",
    delete_alerts_code_scanning:        "Delete code scanning analyses",
    view_secret_scanning_alerts:        "View secret scanning alerts",
    resolve_secret_scanning_alerts:     "Dismiss or reopen secret scanning alerts",
    delete_discussion:                  "Delete a discussion",
    create_discussion_category:         "Create a discussion category",
    edit_discussion_category:           "Edit a discussion category",
    toggle_discussion_answer:           "Mark or unmark discussion answers",
    toggle_discussion_comment_minimize: "Hide or unhide discussion comments",
    convert_issues_to_discussions:      "Convert issues to discussions",
    view_dependabot_alerts:             "View Dependabot alerts",
    resolve_dependabot_alerts:          "Dismiss or reopen Dependabot alerts",
    create_tag:                         "Create a protected tag",
    delete_tag:                         "Delete a protected tag",
    bypass_branch_protection:           "Bypass branch protections",
    edit_repo_protections:              "Edit repository rules",
    edit_repo_announcement_banners:     "Edit repository announcement banners",
    close_discussion:                   "Close a discussion",
    reopen_discussion:                  "Reopen a discussion",
    edit_category_on_discussion:        "Edit category on a discussion",
    edit_discussion_comment:            "Edit a discussion comment",
    manage_discussion_badges:           "Award and revoke discussion badges",
    delete_discussion_comment:          "Delete a discussion comment",
    jump_merge_queue:                   "Jump to the front of the queue",
    create_solo_merge_queue_entry:      "Request a solo merge",
    edit_repo_custom_properties_values: "Edit values of custom properties that allow it",
  }

  CATEGORIES = {
    issues_prs: %i[
      add_assignee
      remove_assignee
      remove_label
      add_label
    ],
    issues: %i[
      close_issue
      reopen_issue
      delete_issue
      mark_as_duplicate
      set_issue_type
    ],
    prs: %i[
      close_pull_request
      reopen_pull_request
      request_pr_review
    ],
    merge_queue: %i[
      jump_merge_queue
      create_solo_merge_queue_entry
    ],
    repository: %i[
      manage_settings_merge_types
      manage_settings_pages
      manage_settings_projects
      manage_settings_wiki
      manage_topics
      push_protected_branch
      set_interaction_limits
      set_milestone
      set_social_preview
      edit_repo_metadata
      manage_deploy_keys
      manage_webhooks
      create_tag
      delete_tag
      bypass_branch_protection
      edit_repo_protections
      edit_repo_announcement_banners
      edit_repo_custom_properties_values
    ],
    security: %i[
      read_code_scanning
      write_code_scanning
      delete_alerts_code_scanning
      view_secret_scanning_alerts
      resolve_secret_scanning_alerts
      view_dependabot_alerts
      resolve_dependabot_alerts
    ],
    discussions: %i[
      convert_issues_to_discussions
      delete_discussion
      edit_discussion_category
      create_discussion_category
      toggle_discussion_answer
      toggle_discussion_comment_minimize
      close_discussion
      reopen_discussion
      edit_category_on_discussion
      edit_discussion_comment
      manage_discussion_badges
      delete_discussion_comment
    ],
  }
end
