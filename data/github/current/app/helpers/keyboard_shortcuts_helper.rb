# typed: true
# frozen_string_literal: true

module KeyboardShortcutsHelper
  extend T::Helpers
  DEFAULT_SEPARATOR = "or"
  TO_SEPARATOR = "to"

  def hotkeys_for(user, scope, shortcut_id)
    shortcuts = keyboard_shortcuts_for(user, scope)
    shortcut = shortcuts.find { |shortcut| shortcut[:id] == shortcut_id }
    return unless shortcut
    shortcut[:hotkeys].join(",") if shortcut[:hotkeys].present?
  end

  def keyboard_shortcuts_for(user, scope, shortcut_list = nil)
    keyboard_shortcuts = shortcut_list || DEFAULT_KEYBOARD_SHORTCUTS

    if keyboard_shortcuts.has_key?(scope)
      visible_shortcuts = keyboard_shortcuts[scope].select do |shortcut|
        show_shortcut = true
        if shortcut[:admin]
          show_shortcut &&= user&.site_admin?
        end
        if shortcut[:required_user_flag]
          show_shortcut &&= GitHub.flipper[shortcut[:required_user_flag]].enabled?(user)
        end
        if shortcut[:except_user_flag]
          show_shortcut &&= !GitHub.flipper[shortcut[:except_user_flag]].enabled?(user)
        end
        if shortcut[:required_feature_preview]
          show_shortcut &&= user&.feature_preview_enabled?(shortcut[:required_feature_preview])
        end
        if shortcut[:hide_on_ghes]
          show_shortcut &&= !GitHub.enterprise?
        end
        if shortcut[:show_on_codespaces_enabled]
          show_shortcut &&= GitHub.codespaces_enabled?
        end
        show_shortcut
      end

      # load any shortcuts that the user can optionally override in UserSettings
      # (must be stored in the format of "#{shortcut[:id]}_hotkey")
      if user
        visible_shortcuts.each do |shortcut|
          if shortcut[:user_settings]
            settings_key = "#{shortcut[:id]}_hotkey"
            hotkey_string = user.settings.get(settings_key)

            if hotkey_string
              shortcut[:hotkeys] = hotkey_string.split(",")

              # use the hotkey string to rebuild the `keys` array,
              # which are used to display the shortcut in the `?` dialog.
              shortcut[:keys] = hotkey_string_to_keys(hotkey_string)
            end
          end
        end
      end

      visible_shortcuts
    else
      []
    end
  end

  def ui_commands_for_contexts(user, contexts)
    keyboard_shortcuts = DEFAULT_KEYBOARD_SHORTCUTS
    split_contexts = contexts.split(",")
    split_contexts.push("global")
    split_contexts.flat_map do |context|
      # the context in the meta tag is "repository" but the context in the keyboard shortcuts is "repositories"
      shortcut_context = context == "repository" ? :repositories : context.to_sym
      shortcuts = keyboard_shortcuts_for(user, shortcut_context)
      transformed_shortcuts = shortcuts.map do |shortcut|
        { id: shortcut[:id], name: shortcut[:label], description: shortcut[:label], keybinding: shortcut[:keys] }
      end
      { context => { service: { id: context, name: context.capitalize }, commands: transformed_shortcuts } } unless shortcuts.empty?
    end
  end

  # Turns a hotkey string like "Mod+k,Mod+Shift+k" into a `keys` format: ["ctrl k", "ctrl shift k"]
  def hotkey_string_to_keys(hotkey_string)
    hotkey_string.split(",").map do |key_combo|
      key_combo.split("+").map do |key|
        key.downcase
          .gsub(/mod/, "ctrl")
          .gsub(/control/, "ctrl")
          .gsub(/none/, "Disabled")
      end.join(" ")
    end
  end

  # Generate page level meta tag with the keyboard shortcuts available
  def keyboard_shortcuts_meta_tag
    contexts = []
    url = T.unsafe(self).canonical_request.path

    before = Time.now
    contexts.push("repository") if T.unsafe(self).current_repository
    contexts.push("code-editor") if url =~ %r{\A/[^/]+/[^/]+/edit/}
    contexts.push("source-code") if url =~ /\/(tree|blob|compare)/
    contexts.push("file-tree") if url =~ /\/(tree|blob)/
    contexts.push("issues") if url =~ /issues/ && url !~ /dashboard\/issues/
    contexts.push("commits") if url =~ /commit\//
    contexts.push("commit-list") if url =~ /(?<![pull\/\d+])\/commits/
    contexts.push("dashboards") if url =~ /\A(\/|\/pulls|\/issues)\Z/
    contexts.push("notifications-v2") if T.unsafe(self).show_notification_shelf? || url =~ /notifications.*/
    contexts.push("pull-request-list", "pull-request-conversation", "pull-request-files-changed") if url =~ /\/pulls?/
    contexts.push("project-cards", "moving-a-card", "moving-columns") if url =~ /projects\/\d+/ && !T.unsafe(self).controller_name.include?("memex")
    contexts.push("network-graph") if url =~ /network/
    contexts.push("checks") if url =~ /\/checks/
    contexts.push("actions") if url =~ /\/runs/ || url =~ /actions/
    contexts.push("memex-table-navigation", "memex-table-manipulation") if url =~ /projects\/(\d+|new)/ && T.unsafe(self).controller_name.include?("memex")
    contexts.push("copilot") if url !~ /\/copilot/
    after = Time.now

    GitHub.dogstats.distribution("keyboard_shortcuts_helper.timing", (after - before) * 1000)
    T.unsafe(self).tag(:meta, name: "github-keyboard-shortcuts", content: contexts.join(","), "data-turbo-transient": true)
  end

  # Caution: changing these constants will directly change
  # the default keyboard shortcut used to open the command palette.
  # See CommandPalette::Hotkey and User::SettingsCollection for more.
  DEFAULT_COMMAND_PALETTE_HOTKEY = "Mod+k,Mod+Alt+k".freeze
  DEFAULT_COMMAND_PALETTE_COMMAND_HOTKEY = "Mod+Shift+K".freeze

  # `keys` is the human-readable shortcut string displayed in the ? dialog
  # `label` is a description of the shortcut displayed in the ? dialog
  # `hotkeys` is the actual shortcut string used in code for data-hotkey
  DEFAULT_KEYBOARD_SHORTCUTS = \
    {
      global: [
        {
          keys: ["ctrl k", "ctrl alt k"],
          id: :command_palette_open,
          label: "Open command palette",
          required_user_flag: :command_palette,
          required_feature_preview: :command_palette,
          user_settings: true,
          hotkeys: DEFAULT_COMMAND_PALETTE_HOTKEY.split(","),
        },
        {
          keys: ["ctrl shift k"],
          id: :command_palette_open_command_mode,
          label: "Open command palette in command mode",
          required_user_flag: :command_palette,
          required_feature_preview: :command_palette,
          user_settings: true,
          hotkeys: DEFAULT_COMMAND_PALETTE_COMMAND_HOTKEY.split(","),
        },
        {
          keys: ["s", "/"],
          id: :search_bar_focus,
          label: "Open search bar",
        },
        {
          keys: ["g n"],
          hotkeys: ["g n"],
          id: :go_to_notifications,
          label: "Go to notifications",
        },
        {
          keys: ["g d"],
          hotkeys: ["g d"],
          id: :go_to_dashboard,
          label: "Go to dashboard",
        },
        {
          keys: ["g i"],
          hotkeys: ["g i"],
          id: :go_to_your_issues,
          label: "Go to your issues",
        },
        {
          keys: ["g p"],
          hotkeys: ["g p"],
          id: :go_to_your_pull_requests,
          label: "Go to your pull requests",
        },
        {
          keys: ["?"],
          id: :keyboard_shortcuts_help,
          label: "Bring up this help dialog",
        },
        {
          keys: ["j"],
          id: :selection_move_down,
          label: "Move selection down",
        },
        {
          keys: ["k"],
          id: :selection_move_up,
          label: "Move selection up",
        },
        {
          keys: ["x"],
          id: :selection_toggle,
          label: "Toggle selection",
        },
        {
          keys: %w[o enter],
          id: :selection_open,
          label: "Open selection",
        },
        {
          keys: ["alt ↑"],
          hotkeys: ["Alt+ArrowUp"],
          id: :expand_hovercard,
          label: "Expand and move focus into focused link's hovercard",
          required_user_flag: :hovercard_accessibility,
        },
        {
          keys: ["shift a"],
          id: :admin_dashboard_open,
          label: "Open site admin dashboard",
          admin: true,
        },
        {
          keys: ["\\"],
          id: :admin_modal_open,
          label: "Open site admin modal",
          admin: true,
        },
      ],
      copilot: [
        {
          keys: ["Shift c"],
          hotkeys: ["Shift+c"],
          id: :copilot_chat_open,
          label: "Open Copilot chat",
        },
        {
          keys: ["Shift x"],
          hotkeys: ["Shift+x"],
          id: :copilot_chat_close,
          label: "Close Copilot chat",
        },
        {
          keys: ["Shift z"],
          hotkeys: ["Shift+z"],
          id: :copilot_chat_expand_collapse,
          label: "Expand/collapse Copilot chat",
        },
      ],
      repositories: [
        {
          keys: [",", "ctrl alt ,"],
          hotkeys: [",", "Mod+Alt+,"],
          id: :codespace_open,
          label: "Open in codespace",
          show_on_codespaces_enabled: true,
        },
        {
          keys: [".", "ctrl alt ."],
          hotkeys: [".", "Mod+Alt+."],
          id: :github_dev_editor_open,
          label: "Open in github.dev editor",
          show_on_codespaces_enabled: true,
        },
        {
          keys: [">"],
          hotkeys: ["Shift+.", "Shift+>", ">"],
          id: :github_dev_editor_open_in_new_tab,
          label: "Open github.dev editor in a new tab",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["ctrl /"],
          id: :secondary_search_bar_focus,
          label: "Focus secondary search bar",
        },
        {
          keys: ["g c"],
          id: :go_to_code,
          label: "Go to Code",
        },
        {
          keys: ["g i"],
          id: :go_to_issues,
          label: "Go to Issues",
        },
        {
          keys: ["g p"],
          id: :go_to_pull_requests,
          label: "Go to Pull Requests",
        },
        {
          keys: ["g a"],
          id: :go_to_actions,
          label: "Go to Actions",
        },
        {
          keys: ["g b"],
          id: :go_to_projects,
          label: "Go to Projects",
        },
        {
          keys: ["g w"],
          id: :go_to_wiki,
          label: "Go to Wiki",
        },
        {
          keys: ["g g"],
          id: :go_to_discussions,
          label: "Go to Discussions",
        },
      ],
      code_editor: [
        {
          keys: ["ctrl shift p"],
          id: :preview_changes,
          label: "Preview changes",
        },
        {
          keys: ["ctrl /"],
          id: :line_comment_toggle,
          label: "Toggle line comment",
        },
        {
          keys: ["ctrl s"],
          hotkeys: ["Meta+s", "Control+s"],
          id: :write_commit_message,
          label: "Write a commit message",
        },
        {
          keys: ["ctrl enter"], # this actually supports both ctrl+enter and cmd+enter – should move to `["Control+Enter", "Meta+Enter"]` when that's available in https://github.com/github/web-systems/issues/360 and https://github.com/github/web-systems/issues/361
          id: :commit_changes,
          label: "Commit changes",
        },
      ],
      source_code: [
        {
          keys: ["t"],
          id: :file_finder_open,
          label: "Jump to file",
        },
        {
          keys: ["l"],
          id: :jump_to_line,
          label: "Jump to line",
        },
        {
          keys: ["w"],
          id: :switch_branch_or_tag,
          label: "Switch branch/tag",
        },
        {
          keys: ["y"],
          id: :url_expand_canonical,
          label: "Expand URL to its canonical form",
        },
        {
          keys: ["i"],
          id: :inline_notes_toggle,
          label: "Show/hide all inline notes",
        },
        {
          keys: ["b"],
          id: :blame_open,
          label: "Open blame",
        },
                {
          keys: ["ctrl shift ."],
          id: :copy_file_path,
          label: "Copy file path",
        },
        {
          keys: ["ctrl shift ,"],
          id: :copy_permalink,
          label: "Copy permalink",
        },
        {
          keys: ["ctrl shift s"],
          id: :download_raw_file,
          label: "Download raw file",
        },
        {
          keys: ["ctrl i"],
          id: :toggle_symbols,
          label: "Toggle symbols panel",
        },
        {
          keys: ["ctrl b"],
          id: :toggle_file_tree,
          label: "Toggle file tree",
        },
        {
          keys: ["ctrl / ctrl c"],
          id: :view_code,
          label: "Open code view",
        },
        {
          keys: ["ctrl / ctrl p"],
          id: :view_preview,
          label: "Open preview",
        },
        {
          keys: ["ctrl / ctrl r"],
          id: :view_raw,
          label: "Open raw file",
        },
      ],
      file_tree: [
        {
          keys: ["a-z"],
          id: :type_ahead,
          label: "Move focus to row starting with string",
          required_user_flag: :code_search_code_view,
        },
        {
          keys: ["↑"],
          id: :focus_previous_row,
          label: "Focus previous row",
          required_user_flag: :code_search_code_view,
        },
        {
          keys: ["↓"],
          id: :focus_next_row,
          label: "Focus next row",
          required_user_flag: :code_search_code_view,
        },
        {
          keys: ["←"],
          id: :collapse_row,
          label: "Collapse row, or focus parent row",
          required_user_flag: :code_search_code_view,
        },
        {
          keys: ["→"],
          id: :Expand_row,
          label: "Expand row, or focus child row",
          required_user_flag: :code_search_code_view,
        },
      ],
      issues: [
        {
          keys: ["ctrl enter"],
          id: :comment_submit,
          label: "Submit comment",
        },
        {
          keys: ["ctrl shift enter"],
          id: :comment_submit_and_close,
          label: "Submit comment and close issue",
        },
        {
          keys: ["ctrl shift p"],
          id: :comment_preview,
          label: "Preview comment",
        },
        {
          keys: ["c"],
          id: :issue_create,
          label: "Create issue",
        },
        {
          keys: ["u"],
          id: :filter_by_author,
          label: "Filter by author",
        },
        {
          keys: ["a"],
          id: :filter_by_assignee,
          label: "Filter by or edit assignees",
        },
        {
          keys: ["l"],
          id: :filter_by_label,
          label: "Filter by or edit labels",
        },
        {
          keys: ["p"],
          id: :filter_by_project,
          label: "Filter by or edit projects",
        },
        {
          keys: ["m"],
          id: :filter_by_milestone,
          label: "Filter by or edit milestones",
        },
        {
          keys: ["t"],
          id: :filter_by_issue_type,
          label: "Filter by or edit issue type",
          required_feature_flag: :issue_types,
        },
        {
          keys: ["d"],
          id: :link_issue_or_pull_request,
          label: "Edit linked issues or pull requests",
          required_feature_flag: :issues_react_v2,
        },
        {
          keys: ["r"],
          id: :reply,
          label: "Reply (quoting selected text)",
        },
        {
          keys: ["ctrl ."],
          id: :saved_replies_open,
          label: "Open saved replies",
        },
        {
          keys: ["ctrl 1", "ctrl 9"],
          id: :saved_replies_insert,
          label: "Insert saved reply (with open saved replies)",
          join: TO_SEPARATOR,
          alwaysCtrl: true
        },
        {
          keys: ["shift alt c"],
          id: :create_sub_issue,
          label: "Create sub-issue",
          required_feature_flag: :sub_issues,
        },
        {
          keys: ["shift alt a"],
          id: :add_existing_issue,
          label: "Add existing issue as sub-issue",
          required_feature_flag: :sub_issues,
        },
        {
          keys: ["shift alt p"],
          id: :edit_parent,
          label: "Edit parent",
          required_feature_flag: :sub_issues,
        },
      ],
      commits: [
        {
          keys: ["ctrl enter"],
          id: :submit,
          label: "Submit comment",
        },
        {
          keys: ["escape"],
          id: :cancel,
          label: "Close form",
        },
        {
          keys: ["p"],
          id: :parent_commit,
          label: "Parent commit",
        },
        {
          keys: ["o"],
          id: :other_parent_commit,
          label: "Other parent commit",
        },
      ],
      commit_list: [
        {
          keys: ["y"],
          id: :url_expand_canonical,
          label: "Expand URL to its canonical form",
        },
      ],
      notifications: [
        {
          keys: %w[e I y],
          id: :mark_as_read,
          label: "Mark as read",
        },
        {
          keys: ["shift m"],
          id: :mute_thread,
          label: "Mute thread",
        },
      ],
      notifications_v2: [
        {
          keys: ["e"],
          id: :mark_as_done,
          label: "Mark as done",
        },
        {
          keys: ["shift i"],
          id: :mark_as_read,
          label: "Mark as read",
        },
        {
          keys: ["shift u"],
          id: :mark_as_unread,
          label: "Mark as unread",
        },
        {
          keys: ["shift m"],
          id: :unsubscribe,
          label: "Unsubscribe",
        },
      ],
      moving_columns: [
        {
          keys: %w[enter space],
          id: :column_move_start,
          label: "Start moving the focused column",
        },
        {
          keys: ["escape"],
          id: :column_move_cancel,
          label: "Cancel the move in progress",
        },
        {
          keys: ["enter"],
          id: :column_move_confirm,
          label: "Complete the move in progress",
        },
        {
          keys: ["←", "h"],
          id: :column_move_left,
          label: "Move column to the left",
        },
        {
          keys: ["ctrl ←", "ctrl h"],
          id: :column_move_leftmost,
          label: "Move column to the leftmost position",
        },
        {
          keys: ["→", "l"],
          id: :column_move_right,
          label: "Move column to the right",
        },
        {
          keys: ["ctrl →", "ctrl l"],
          id: :column_move_rightmost,
          label: "Move column to the rightmost position",
        },
      ],
      project_cards: [
        {
          keys: ["d"],
          id: :open_associated_issue_or_pull_request,
          label: "Open the issue or pull request associated with the focused card in the sidebar",
        },
      ],
      pull_request_list: [
        {
          keys: %w[o enter],
          id: :pull_request_open,
          label: "Open pull request",
        },
      ],
      pull_request_conversation: [
        {
          keys: ["."],
          id: :github_dev_editor_open,
          label: "Open in github.dev editor",
          show_on_codespaces_enabled: true,
        },
        {
          keys: [">"],
          hotkeys: ["Shift+.", "Shift+>", ">"],
          id: :github_dev_editor_open_in_new_tab,
          label: "Open github.dev editor in a new tab",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["ctrl enter"],
          id: :comment_submit,
          label: "Submit comment",
        },
        {
          keys: ["ctrl shift enter"],
          id: :comment_submit_and_close,
          label: "Submit comment and close or open pull request",
        },
        {
          keys: ["ctrl shift p"],
          id: :comment_preview,
          label: "Preview comment",
        },
        {
          keys: ["q"],
          id: :request_reviewers,
          label: "Request reviewers",
        },
        {
          keys: ["a"],
          id: :filter_by_assignee,
          label: "Filter by or edit assignees",
        },
        {
          keys: ["l"],
          id: :filter_by_label,
          label: "Filter by or edit labels",
        },
        {
          keys: ["p"],
          id: :filter_by_project,
          label: "Filter by or edit projects",
        },
        {
          keys: ["m"],
          id: :filter_by_milestone,
          label: "Filter by or edit milestones",
        },
        {
          keys: ["x"],
          hotkeys: ["x"],
          id: :link_an_issue_or_pull_request,
          label: "Link an issue or pull request from the same repository"
        },
        {
          keys: ["r"],
          hotkeys: ["r"],
          id: :reply,
          label: "Reply (quoting selected text)",
        },
        {
          keys: ["ctrl ."],
          id: :saved_replies_open,
          label: "Open saved replies",
        },
        {
          keys: ["ctrl 1", "ctrl 9"],
          id: :saved_replies_insert,
          label: "Insert saved reply (with open saved replies)",
          join: TO_SEPARATOR,
          alwaysCtrl: true
        },
        {
          keys: ["Alt"],
          id: :comments_toggle_all_collapsed,
          label: "Toggle visibility of all collapsed review comments instead of just the current one",
          hold: true,
        },
        {
          keys: ["shift alt c"],
          id: :create_sub_issue,
          label: "Create sub-issue",
        },
        {
          keys: ["shift alt a"],
          id: :add_existing_issue,
          label: "Add existing issue as sub-issue",
        },
        {
          keys: ["shift alt p"],
          id: :edit_parent,
          label: "Assign parent",
        },
      ],
      pull_request_files_changed: [
        {
          keys: ["."],
          id: :github_dev_editor_open,
          label: "Open in github.dev editor",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["Shift+.", "Shift+>", ">"],
          id: :github_dev_editor_open_in_new_tab,
          label: "Open github.dev editor in a new tab",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["c"],
          id: :commits_list_open,
          label: "Open commits list",
        },
        {
          id: :files_list_open,
          label: "Open files list",
          keys: ["t"],
          hotkeys: ["t"],
        },
        {
          keys: ["n"],
          id: :commit_go_to_next,
          label: "Next commit",
        },
        {
          keys: ["p"],
          id: :commit_go_to_previous,
          label: "Previous commit",
        },
        {
          keys: ["a"],
          id: :annotations_toggle,
          label: "Show or hide annotations",
        },
        {
          keys: ["i"],
          id: :comments_toggle,
          label: "Show or hide comments",
        },
        {
          keys: ["ctrl shift enter"],
          id: :comment_submit,
          label: "Submit a review comment",
        },
        {
          keys: ["Alt"],
          id: :files_toggle_all_collapsed,
          label: "Collapse or expand all files instead of just the current one",
          hold: true,
        },
        {
          keys: ["escape"],
          id: :close_conversation_detail_panel,
          label: "Close the focused conversation",
          required_user_flag: :prx,
        },
      ],
      network_graph: [
        {
          keys: ["←", "h"],
          id: :scroll_left,
          label: "Scroll left",
        },
        {
          keys: ["→", "l"],
          id: :scroll_right,
          label: "Scroll right",
        },
        {
          keys: ["↑", "k"],
          id: :scroll_up,
          label: "Scroll up",
        },
        {
          keys: ["↓", "j"],
          id: :scroll_down,
          label: "Scroll down",
        },
        {
          keys: ["t"],
          id: :labels_toggle,
          label: "Toggle visibility of the head labels",
        },
        {
          keys: ["shift ←", "shift h"],
          id: :scroll_leftmost,
          label: "Scroll all the way left",
        },
        {
          keys: ["shift →", "shift l"],
          id: :scroll_rightmost,
          label: "Scroll all the way right",
        },
        {
          keys: ["shift ↑", "shift k"],
          id: :scroll_top,
          label: "Scroll all the way up",
        },
        {
          keys: ["shift ↓", "shift j"],
          id: :scroll_bottom,
          label: "Scroll all the way down",
        },
      ],
      moving_a_card: [
        {
          keys: %w[enter space],
          id: :card_move_start,
          label: "Start moving the focused card",
        },
        {
          keys: ["escape"],
          id: :card_move_cancel,
          label: "Cancel the move in progress",
        },
        {
          keys: ["enter"],
          id: :card_move_confirm,
          label: "Complete the move in progress",
        },
        {
          keys: ["↓", "j"],
          id: :card_move_down,
          label: "Move card down",
        },
        {
          keys: ["ctrl ↓", "ctrl j"],
          id: :card_move_bottom,
          label: "Move card to the bottom of the column",
        },
        {
          keys: ["↑", "k"],
          id: :card_move_up,
          label: "Move card up",
        },
        {
          keys: ["ctrl ↑", "ctrl k"],
          id: :card_move_top,
          label: "Move card to the top of the column",
        },
        {
          keys: ["←", "h"],
          id: :card_move_left_bottom,
          label: "Move card to the bottom of the column on the left",
        },
        {
          keys: ["shift ←", "shift h"],
          id: :card_move_left_top,
          label: "Move card to the top of the column on the left",
        },
        {
          keys: ["ctrl ←", "ctrl h"],
          id: :card_move_leftmost_bottom,
          label: "Move card to the bottom of the leftmost column",
        },
        {
          keys: ["ctrl shift ←", "ctrl shift h"],
          id: :card_move_leftmost_top,
          label: "Move card to the top of the leftmost column",
        },
        {
          keys: ["→", "l"],
          id: :card_move_right_bottom,
          label: "Move card to the bottom of the column on the right",
        },
        {
          keys: ["shift →", "shift l"],
          id: :card_move_right_top,
          label: "Move card to the top of the column on the right",
        },
        {
          keys: ["ctrl →", "ctrl l"],
          id: :card_move_rightmost_bottom,
          label: "Move card to the bottom of the rightmost column",
        },
        {
          keys: ["ctrl shift →", "ctrl shift l"],
          id: :card_move_rightmost_top,
          label: "Move card to the top of the rightmost column",
        },
      ],
      checks: [
        {
          keys: ["c"],
          id: :commit_menu_open,
          label: "Open the commit menu",
        },
      ],
      actions: [
        {
          keys: ["g u"],
          hotkeys: ["g u"],
          id: :go_to_usage,
          label: "Go to usage",
          hide_on_ghes: true,
        },
        {
          keys: ["g f"],
          hotkeys: ["g f"],
          id: :go_to_workflow_file,
          label: "Go to workflow file",
        },
        {
          keys: ["shift t"],
          id: :timestamps_toggle,
          label: "Toggle timestamps in logs",
        },
        {
          keys: ["shift f"],
          id: :fullscreen_logs_toggle,
          label: "Toggle fullscreen logs",
        },
        {
          keys: ["esc"],
          id: :fullscreen_logs_exit,
          label: "Exit fullscreen logs",
        },
        {
          hotkeys: ["Control+/"],
          keys: ["Control+/"],
          id: :actions_main_view_search_bar,
          label: "Actions main view search bar",
        },
      ],
      memex_table_navigation: [
        {
          keys: ["ctrl k"],
          id: :command_palette_open,
          label: "Open command palette",
        },
        {
          keys: ["ctrl /"],
          id: :filter_field_focus,
          label: "Focus filter field",
        },
        {
          keys: ["←", "shift tab"],
          id: :cell_focus_left,
          label: "Move cell focus to the left",
        },
        {
          keys: ["→", "tab"],
          id: :cell_focus_right,
          label: "Move cell focus to the right",
        },
        {
          keys: ["↑"],
          id: :cell_focus_up,
          label: "Move cell focus up",
        },
        {
          keys: ["↓"],
          id: :cell_focus_down,
          label: "Move cell focus down",
        },
        {
          keys: ["ctrl f6"],
          id: :focus_side_panel,
          label: "Move focus to/from side panel"
        },
      ],
      tasklist_block_navigation: [
        {
          keys: ["↑"],
          id: :tasklist_item_focus_up,
          label: "Move Tasklist Item focus up",
        },
        {
          keys: ["↓"],
          id: :tasklist_item_focus_down,
          label: "Move Tasklist Item focus down",
        },
        {
          keys: ["shift tab"],
          id: :taklist_item_focus_left,
          label: "Move item menu focus focus to the left",
        },
        {
          keys: ["tab"],
          id: :taklist_item_focus_right,
          label: "Move item menu focus focus to the right",
        },
        {
          keys: ["esc"],
          id: :tasklist_item_focus_cancel,
          label: "Cancel focus for the tasklist items contents",
        },
        {
          keys: ["space"],
          id: :tasklist_item_focus_contents,
          label: "Focus into the tasklist item contents",
        },
        {
          keys: ["home"],
          id: :tasklist_item_focus_first,
          label: "Move tasklist item focus to the first item in the list",
        },
        {
          keys: ["end"],
          id: :tasklist_item_focus_last,
          label: "Move tasklist item focus to the last item in the list",
        },
      ],
      memex_table_manipulation: [
        {
          keys: ["enter"],
          id: :cell_edit_start,
          label: "Toggle edit mode for the focused cell",
        },
        {
          keys: ["esc"],
          id: :cell_edit_cancel,
          label: "Cancel editing for the focused cell",
        },
        {
          keys: ["ctrl d"],
          hotkeys: ["Meta+d", "Control+d"],
          label: "Fill selected cells down",
        },
        {
          keys: ["ctrl shift \\"],
          id: :action_menu_open,
          label: "Open row actions menu",
        },
        {
          keys: ["shift space"],
          label: "Select item",
        },
        {
          keys: ["space"],
          id: :open_selected_item,
          label: "Open selected item"
        },
        {
          keys: ["e"],
          id: :archive,
          label: "Archive items",
        }
      ]
    }.freeze
end
