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

  def keyboard_shortcuts_for(user, scope, contexts = [])
    keyboard_shortcuts = DEFAULT_KEYBOARD_SHORTCUTS

    if keyboard_shortcuts.has_key?(scope)
      visible_shortcuts = keyboard_shortcuts[scope].select do |shortcut|
        show_shortcut = true
        if shortcut[:admin]
          show_shortcut &&= user&.site_admin?
        end
        if shortcut[:required_user_flag]
          show_shortcut &&= FeatureFlag.vexi.enabled_or_raise?(shortcut[:required_user_flag], user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        end
        if shortcut[:except_user_flag]
          show_shortcut &&= !FeatureFlag.vexi.enabled_or_raise?(shortcut[:except_user_flag], user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
        if shortcut[:hide_on_contexts]
          show_shortcut &&= (shortcut[:hide_on_contexts] & contexts).empty?
        end
        if shortcut[:hide_when_react_nav]
          show_shortcut &&= !(user &&
            FeatureFlag.vexi.enabled?(:global_nav_react, user, default: false))
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

  sig { params(user: T.nilable(User), contexts: String).returns(T::Array[T.untyped]) }
  def ui_commands_for_contexts(user, contexts)
    keyboard_shortcuts = DEFAULT_KEYBOARD_SHORTCUTS
    split_contexts = contexts.split(",")
    split_contexts.push("global")
    split_contexts.flat_map do |context|
      # the context in the meta tag is "repository" but the context in the keyboard shortcuts is "repositories"
      shortcut_context = context == "repository" ? :repositories : context.to_sym
      shortcuts = keyboard_shortcuts_for(user, shortcut_context, split_contexts)
      transformed_shortcuts = shortcuts.map do |shortcut|
        { id: shortcut[:id], name: shortcut[:label], description: shortcut[:label], keybinding: shortcut[:hotkeys], hold: shortcut[:hold] }
      end
      { shortcut_context.to_s => { service: { id: shortcut_context, name: DEFAULT_KEYBOARD_SHORTCUTS_TITLES[shortcut_context] }, commands: transformed_shortcuts } } unless shortcuts.empty?
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
    contexts.push("workspace_editor") if GitHub.context[:workspace_editor_route]
    contexts.push("repository") if T.unsafe(self).current_repository && !GitHub.context[:workspace_editor_route]
    contexts.push("code-editor") if url =~ %r{\A/[^/]+/[^/]+/edit/} && !GitHub.context[:workspace_editor_route]
    contexts.push("source-code") if url =~ /\/(tree|blob|compare)/
    contexts.push("file-tree") if url =~ /\/(tree|blob)/
    contexts.push("issues") if url =~ /issues/ && url !~ /dashboard\/issues/
    contexts.push("commits") if url =~ /commit\//
    contexts.push("commit-list") if url =~ /(?<![pull\/\d+])\/commits/
    contexts.push("dashboards") if url =~ /\A(\/|\/pulls|\/issues)\Z/
    contexts.push("notifications-v2") if T.unsafe(self).show_notification_shelf? || url =~ /notifications.*/
    contexts.push("pull-request-list", "pull-request-conversation", "pull-request-files-changed") if url =~ /\/pulls?/ && !GitHub.context[:workspace_editor_route]
    contexts.push("project-cards", "moving-a-card", "moving-columns") if url =~ /projects\/\d+/ && !T.unsafe(self).controller_name.include?("memex")
    contexts.push("network-graph") if url =~ /network/
    contexts.push("checks") if url =~ /\/checks/
    contexts.push("actions") if url =~ /\/runs/ || url =~ /actions/
    contexts.push("memex-table-navigation", "memex-table-manipulation") if url =~ /projects\/(\d+|new)/ && T.unsafe(self).controller_name.include?("memex")
    contexts.push("copilot") if url !~ /\A\/copilot/ && !GitHub.context[:workspace_editor_route]
    after = Time.now

    GitHub.dogstats.distribution("keyboard_shortcuts_helper.timing", (after - before) * 1000)
    T.unsafe(self).tag(:meta, name: "github-keyboard-shortcuts", content: contexts.join(","), "data-turbo-transient": true)
  end

  # Caution: changing these constants will directly change
  # the default keyboard shortcut used to open the command palette.
  # See CommandPalette::Hotkey and User::SettingsCollection for more.
  DEFAULT_COMMAND_PALETTE_HOTKEY = "Mod+k,Mod+Alt+k".freeze
  DEFAULT_COMMAND_PALETTE_COMMAND_HOTKEY = "Mod+Shift+K".freeze

  # `hotkeys` is the actual shortcut string used in code for data-hotkey and displayed by the new React ? dialog
  # `keys` is the human-readable shortcut string displayed in the old (deprecated) ? dialog partial
  # `label` is a description of the shortcut displayed in the ? dialog
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
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: ["ctrl shift k"],
          id: :command_palette_open_command_mode,
          label: "Open command palette in command mode",
          required_user_flag: :command_palette,
          required_feature_preview: :command_palette,
          user_settings: true,
          hotkeys: DEFAULT_COMMAND_PALETTE_COMMAND_HOTKEY.split(","),
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: ["s", "/"],
          hotkeys: %w[s /],
          id: :search_bar_focus,
          label: "Open search bar",
          hide_on_contexts: ["workspace_editor"],
          hide_when_react_nav: true,
        },
        {
          keys: ["g n"],
          hotkeys: ["g n"],
          id: :go_to_notifications,
          label: "Go to notifications",
          hide_on_contexts: ["workspace_editor"],
          hide_when_react_nav: true,
        },
        {
          keys: ["g d"],
          hotkeys: ["g d"],
          id: :go_to_dashboard,
          label: "Go to dashboard",
          hide_when_react_nav: true,
        },
        {
          keys: ["g i"],
          hotkeys: ["g i"],
          id: :go_to_your_issues,
          label: "Go to your issues",
          hide_when_react_nav: true,
        },
        {
          keys: ["g p"],
          hotkeys: ["g p"],
          id: :go_to_your_pull_requests,
          label: "Go to your pull requests",
          hide_when_react_nav: true,
        },
        {
          keys: ["?"],
          hotkeys: ["Shift+?"],
          id: :keyboard_shortcuts_help,
          label: "Bring up this help dialog",
          hide_when_react_nav: true,
        },
        {
          keys: ["j"],
          hotkeys: ["j"],
          id: :selection_move_down,
          label: "Move selection down",
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: ["k"],
          hotkeys: ["k"],
          id: :selection_move_up,
          label: "Move selection up",
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: ["x"],
          hotkeys: ["x"],
          id: :selection_toggle,
          label: "Toggle selection",
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: %w[o enter],
          hotkeys: %w[o Enter],
          id: :selection_open,
          label: "Open selection",
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: ["alt ↑"],
          hotkeys: ["Alt+ArrowUp"],
          id: :expand_hovercard,
          label: "Expand and move focus into focused link's hovercard",
          hide_on_contexts: ["workspace_editor"]
        },
        {
          keys: ["shift a"],
          hotkeys: ["Shift+A"],
          id: :admin_dashboard_open,
          label: "Open site admin dashboard",
          admin: true,
        },
        {
          keys: ["\\"],
          hotkeys: ["\\"],
          id: :admin_modal_open,
          label: "Open site admin modal",
          admin: true,
          hide_on_contexts: ["workspace_editor"]
        },
      ],
      repositories: [
        {
          keys: [",", "ctrl alt ,"],
          hotkeys: %w[, Mod+Alt+,],
          id: :codespace_open,
          label: "Open in codespace",
          show_on_codespaces_enabled: true,
        },
        {
          keys: [".", "ctrl alt ."],
          hotkeys: %w[. Mod+Alt+.],
          id: :github_dev_editor_open,
          label: "Open in github.dev editor",
          show_on_codespaces_enabled: true,
        },
        {
          keys: [">"],
          hotkeys: ["Shift+>"],
          id: :github_dev_editor_open_in_new_tab,
          label: "Open github.dev editor in a new tab",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["ctrl /"],
          hotkeys: ["Mod+/"],
          id: :secondary_search_bar_focus,
          label: "Focus secondary search bar",
        },
        {
          keys: ["g c"],
          hotkeys: ["g c"],
          id: :go_to_code,
          label: "Go to Code",
          hide_when_react_nav: true,
        },
        {
          keys: ["g i"],
          hotkeys: ["g i"],
          id: :go_to_issues,
          label: "Go to Issues",
          hide_when_react_nav: true,
        },
        {
          keys: ["g p"],
          hotkeys: ["g p"],
          id: :go_to_pull_requests,
          label: "Go to Pull Requests",
          hide_when_react_nav: true,
        },
        {
          keys: ["g a"],
          hotkeys: ["g a"],
          id: :go_to_actions,
          label: "Go to Actions",
          hide_when_react_nav: true,
        },
        {
          keys: ["g b"],
          hotkeys: ["g b"],
          id: :go_to_projects,
          label: "Go to Projects",
          hide_when_react_nav: true,
        },
        {
          keys: ["g w"],
          hotkeys: ["g w"],
          id: :go_to_wiki,
          label: "Go to Wiki",
          hide_when_react_nav: true,
        },
        {
          keys: ["g g"],
          hotkeys: ["g g"],
          id: :go_to_discussions,
          label: "Go to Discussions",
          hide_when_react_nav: true,
        },
      ],
      code_editor: [
        {
          keys: ["ctrl shift p"],
          hotkeys: ["Mod+Shift+P"],
          id: :preview_changes,
          label: "Preview changes",
        },
        {
          keys: ["ctrl /"],
          hotkeys: ["Mod+/"],
          id: :line_comment_toggle,
          label: "Toggle line comment",
        },
        {
          keys: ["ctrl s"],
          hotkeys: %w[Meta+s Control+s],
          id: :write_commit_message,
          label: "Write a commit message",
        },
        {
          keys: ["ctrl enter"],
          hotkeys: ["Mod+Enter"],
          id: :commit_changes,
          label: "Commit changes",
        },
      ],
      source_code: [
        {
          keys: ["t"],
          hotkeys: ["t"],
          id: :file_finder_open,
          label: "Jump to file",
        },
        {
          keys: ["l"],
          hotkeys: ["l"],
          id: :jump_to_line,
          label: "Jump to line",
        },
        {
          keys: ["w"],
          hotkeys: ["w"],
          id: :switch_branch_or_tag,
          label: "Switch branch/tag",
        },
        {
          keys: ["y"],
          hotkeys: ["y"],
          id: :url_expand_canonical,
          label: "Expand URL to its canonical form",
        },
        {
          keys: ["i"],
          hotkeys: ["i"],
          id: :inline_notes_toggle,
          label: "Show/hide all inline notes",
        },
        {
          keys: ["b"],
          hotkeys: ["b"],
          id: :blame_open,
          label: "Open blame",
        },
                {
          keys: ["ctrl shift ."],
          hotkeys: ["Mod+Shift+."],
          id: :copy_file_path,
          label: "Copy file path",
        },
        {
          keys: ["ctrl shift ,"],
          hotkeys: ["Mod+Shift+,"],
          id: :copy_permalink,
          label: "Copy permalink",
        },
        {
          keys: ["ctrl shift s"],
          hotkeys: ["Mod+Shift+S"],
          id: :download_raw_file,
          label: "Download raw file",
        },
        {
          keys: ["ctrl i"],
          hotkeys: ["Mod+i"],
          id: :toggle_symbols,
          label: "Toggle symbols panel",
        },
        {
          keys: ["ctrl b"],
          hotkeys: ["Mod+b"],
          id: :toggle_file_tree,
          label: "Toggle file tree",
        },
        {
          keys: ["ctrl / ctrl c"],
          hotkeys: ["Mod+/ Mod+c"],
          id: :view_code,
          label: "Open code view",
        },
        {
          keys: ["ctrl / ctrl p"],
          hotkeys: ["Mod+/ Mod+p"],
          id: :view_preview,
          label: "Open preview",
        },
        {
          keys: ["ctrl / ctrl r"],
          hotkeys: ["Mod+/ Mod+r"],
          id: :view_raw,
          label: "Open raw file",
        },
      ],
      file_tree: [
        {
          keys: ["a-z"],
          hotkeys: %w[a z],
          id: :type_ahead,
          label: "Move focus to row starting with string",
        },
        {
          keys: ["↑"],
          hotkeys: ["ArrowUp"],
          id: :focus_previous_row,
          label: "Focus previous row",
        },
        {
          keys: ["↓"],
          hotkeys: ["ArrowDown"],
          id: :focus_next_row,
          label: "Focus next row",
        },
        {
          keys: ["←"],
          hotkeys: ["ArrowLeft"],
          id: :collapse_row,
          label: "Collapse row, or focus parent row",
        },
        {
          keys: ["→"],
          hotkeys: ["ArrowRight"],
          id: :Expand_row,
          label: "Expand row, or focus child row",
        },
      ],
      issues: [
        {
          keys: ["ctrl enter"],
          hotkeys: ["Mod+Enter"],
          id: :comment_submit,
          label: "Submit comment",
        },
        {
          keys: ["ctrl shift enter"],
          hotkeys: ["Mod+Shift+Enter"],
          id: :comment_submit_and_close,
          label: "Submit comment and close issue",
        },
        {
          keys: ["ctrl shift p"],
          hotkeys: ["Mod+Shift+P"],
          id: :comment_preview,
          label: "Preview comment",
        },
        {
          keys: ["c"],
          hotkeys: ["c"],
          id: :issue_create,
          label: "Create issue",
        },
        {
          keys: ["u"],
          hotkeys: ["u"],
          id: :filter_by_author,
          label: "Filter by author",
        },
        {
          keys: ["a"],
          hotkeys: ["a"],
          id: :filter_by_assignee,
          label: "Filter by or edit assignees",
        },
        {
          keys: ["l"],
          hotkeys: ["l"],
          id: :filter_by_label,
          label: "Filter by or edit labels",
        },
        {
          keys: ["p"],
          hotkeys: ["p"],
          id: :filter_by_project,
          label: "Filter by or edit projects",
        },
        {
          keys: ["m"],
          hotkeys: ["m"],
          id: :filter_by_milestone,
          label: "Filter by or edit milestones",
        },
        {
          keys: ["t"],
          hotkeys: ["t"],
          id: :filter_by_issue_type,
          label: "Filter by or edit issue type",
        },
        {
          keys: ["d"],
          hotkeys: ["d"],
          id: :link_issue_or_pull_request,
          label: "Edit linked issues or pull requests",
        },
        {
          keys: ["r"],
          hotkeys: ["r"],
          id: :reply,
          label: "Reply (quoting selected text)",
        },
        {
          keys: ["ctrl ."],
          hotkeys: ["Mod+."],
          id: :saved_replies_open,
          label: "Open saved replies",
        },
        {
          keys: ["ctrl 1", "ctrl 9"],
          hotkeys: %w[Ctrl+1 Ctrl+9],
          id: :saved_replies_insert,
          label: "Insert saved reply (with open saved replies)",
          join: TO_SEPARATOR,
          alwaysCtrl: true
        },
        {
          keys: ["shift alt c"],
          hotkeys: ["Alt+Shift+C"],
          id: :create_sub_issue,
          label: "Create sub-issue",
        },
        {
          keys: ["shift alt a"],
          hotkeys: ["Alt+Shift+A"],
          id: :add_existing_issue,
          label: "Add existing issue as sub-issue",
        },
        {
          keys: ["shift alt p"],
          hotkeys: ["Alt+Shift+P"],
          id: :edit_parent,
          label: "Edit parent",
        },
      ],
      commits: [
        {
          keys: ["ctrl enter"],
          hotkeys: ["Mod+Enter"],
          id: :submit,
          label: "Submit comment",
        },
        {
          keys: ["escape"],
          hotkeys: ["Escape"],
          id: :cancel,
          label: "Close form",
        },
        {
          keys: ["p"],
          hotkeys: ["p"],
          id: :parent_commit,
          label: "Parent commit",
        },
        {
          keys: ["o"],
          hotkeys: ["o"],
          id: :other_parent_commit,
          label: "Other parent commit",
        },
      ],
      commit_list: [
        {
          keys: ["y"],
          hotkeys: ["y"],
          id: :url_expand_canonical,
          label: "Expand URL to its canonical form",
        },
      ],
      notifications: [
        {
          keys: %w[e I y],
          hotkeys: %w[e Shift+I y],
          id: :mark_as_read,
          label: "Mark as read",
        },
        {
          keys: ["shift m"],
          hotkeys: ["Shift+M"],
          id: :mute_thread,
          label: "Mute thread",
        },
      ],
      notifications_v2: [
        {
          keys: ["e"],
          hotkeys: ["e"],
          id: :mark_as_done,
          label: "Mark as done",
        },
        {
          keys: ["shift i"],
          hotkeys: ["Shift+I"],
          id: :mark_as_read,
          label: "Mark as read",
        },
        {
          keys: ["shift u"],
          hotkeys: ["Shift+U"],
          id: :mark_as_unread,
          label: "Mark as unread",
        },
        {
          keys: ["shift m"],
          hotkeys: ["Shift+M"],
          id: :unsubscribe,
          label: "Unsubscribe",
        },
      ],
      moving_columns: [
        {
          keys: %w[enter space],
          hotkeys: %w[Enter Space],
          id: :column_move_start,
          label: "Start moving the focused column",
        },
        {
          keys: ["escape"],
          hotkeys: ["Escape"],
          id: :column_move_cancel,
          label: "Cancel the move in progress",
        },
        {
          keys: ["enter"],
          hotkeys: ["Enter"],
          id: :column_move_confirm,
          label: "Complete the move in progress",
        },
        {
          keys: ["←", "h"],
          hotkeys: %w[ArrowLeft h],
          id: :column_move_left,
          label: "Move column to the left",
        },
        {
          keys: ["ctrl ←", "ctrl h"],
          hotkeys: %w[Mod+ArrowLeft Mod+h],
          id: :column_move_leftmost,
          label: "Move column to the leftmost position",
        },
        {
          keys: ["→", "l"],
          hotkeys: %w[ArrowRight l],
          id: :column_move_right,
          label: "Move column to the right",
        },
        {
          keys: ["ctrl →", "ctrl l"],
          hotkeys: %w[Mod+ArrowRight Mod+l],
          id: :column_move_rightmost,
          label: "Move column to the rightmost position",
        },
      ],
      project_cards: [
        {
          keys: ["d"],
          hotkeys: ["d"],
          id: :open_associated_issue_or_pull_request,
          label: "Open the issue or pull request associated with the focused card in the sidebar",
        },
      ],
      pull_request_list: [
        {
          keys: %w[o enter],
          hotkeys: %w[o Enter],
          id: :pull_request_open,
          label: "Open pull request",
        },
      ],
      pull_request_conversation: [
        {
          keys: ["."],
          hotkeys: ["."],
          id: :github_dev_editor_open,
          label: "Open in github.dev editor",
          show_on_codespaces_enabled: true,
        },
        {
          keys: [">"],
          hotkeys: ["Shift+>"],
          id: :github_dev_editor_open_in_new_tab,
          label: "Open github.dev editor in a new tab",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["ctrl enter"],
          hotkeys: ["Mod+Enter"],
          id: :comment_submit,
          label: "Submit comment",
        },
        {
          keys: ["ctrl shift enter"],
          hotkeys: ["Mod+Shift+Enter"],
          id: :comment_submit_and_close,
          label: "Submit comment and close or open pull request",
        },
        {
          keys: ["ctrl shift p"],
          hotkeys: ["Mod+Shift+P"],
          id: :comment_preview,
          label: "Preview comment",
        },
        {
          keys: ["q"],
          hotkeys: ["q"],
          id: :request_reviewers,
          label: "Request reviewers",
        },
        {
          keys: ["a"],
          hotkeys: ["a"],
          id: :filter_by_assignee,
          label: "Filter by or edit assignees",
        },
        {
          keys: ["l"],
          hotkeys: ["l"],
          id: :filter_by_label,
          label: "Filter by or edit labels",
        },
        {
          keys: ["p"],
          hotkeys: ["p"],
          id: :filter_by_project,
          label: "Filter by or edit projects",
        },
        {
          keys: ["m"],
          hotkeys: ["m"],
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
          hotkeys: ["Mod+."],
          id: :saved_replies_open,
          label: "Open saved replies",
        },
        {
          keys: ["ctrl 1", "ctrl 9"],
          hotkeys: %w[Ctrl+1 Ctrl+9],
          id: :saved_replies_insert,
          label: "Insert saved reply (with open saved replies)",
          join: TO_SEPARATOR,
          alwaysCtrl: true
        },
        {
          keys: ["Alt"],
          hotkeys: ["Alt"],
          id: :comments_toggle_all_collapsed,
          label: "Toggle visibility of all collapsed review comments instead of just the current one",
          hold: true,
        },
        {
          keys: ["shift alt c"],
          hotkeys: ["Alt+Shift+C"],
          id: :create_sub_issue,
          label: "Create sub-issue",
        },
        {
          keys: ["shift alt a"],
          hotkeys: ["Alt+Shift+A"],
          id: :add_existing_issue,
          label: "Add existing issue as sub-issue",
        },
        {
          keys: ["shift alt p"],
          hotkeys: ["Alt+Shift+P"],
          id: :edit_parent,
          label: "Assign parent",
        },
      ],
      pull_request_files_changed: [
        {
          keys: ["."],
          hotkeys: ["."],
          id: :github_dev_editor_open,
          label: "Open in github.dev editor",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["Shift+.", "Shift+>", ">"],
          hotkeys: ["Shift+>"],
          id: :github_dev_editor_open_in_new_tab,
          label: "Open github.dev editor in a new tab",
          show_on_codespaces_enabled: true,
        },
        {
          keys: ["c"],
          hotkeys: ["c"],
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
          hotkeys: ["n"],
          id: :commit_go_to_next,
          label: "Next commit",
        },
        {
          keys: ["p"],
          hotkeys: ["p"],
          id: :commit_go_to_previous,
          label: "Previous commit",
        },
        {
          keys: ["a"],
          hotkeys: ["a"],
          id: :annotations_toggle,
          label: "Show or hide annotations",
        },
        {
          keys: ["i"],
          hotkeys: ["i"],
          id: :comments_toggle,
          label: "Show or hide comments",
        },
        {
          keys: ["ctrl shift enter"],
          hotkeys: ["Mod+Shift+Enter"],
          id: :comment_submit,
          label: "Submit a review comment",
        },
        {
          keys: ["Alt"],
          hotkeys: ["Alt"],
          id: :files_toggle_all_collapsed,
          label: "Collapse or expand all files instead of just the current one",
          hold: true,
        },
        {
          keys: ["escape"],
          hotkeys: ["Escape"],
          id: :close_conversation_detail_panel,
          label: "Close the focused conversation",
          required_user_flag: :prx_files,
        },
      ],
      network_graph: [
        {
          keys: ["←", "h"],
          hotkeys: %w[ArrowLeft h],
          id: :scroll_left,
          label: "Scroll left",
        },
        {
          keys: ["→", "l"],
          hotkeys: %w[ArrowRight l],
          id: :scroll_right,
          label: "Scroll right",
        },
        {
          keys: ["↑", "k"],
          hotkeys: %w[ArrowUp k],
          id: :scroll_up,
          label: "Scroll up",
        },
        {
          keys: ["↓", "j"],
          hotkeys: %w[ArrowDown j],
          id: :scroll_down,
          label: "Scroll down",
        },
        {
          keys: ["t"],
          hotkeys: ["t"],
          id: :labels_toggle,
          label: "Toggle visibility of the head labels",
        },
        {
          keys: ["shift ←", "shift h"],
          hotkeys: %w[Shift+ArrowLeft Shift+H],
          id: :scroll_leftmost,
          label: "Scroll all the way left",
        },
        {
          keys: ["shift →", "shift l"],
          hotkeys: %w[Shift+ArrowRight Shift+L],
          id: :scroll_rightmost,
          label: "Scroll all the way right",
        },
        {
          keys: ["shift ↑", "shift k"],
          hotkeys: %w[Shift+ArrowUp Shift+K],
          id: :scroll_top,
          label: "Scroll all the way up",
        },
        {
          keys: ["shift ↓", "shift j"],
          hotkeys: %w[Shift+ArrowDown Shift+J],
          id: :scroll_bottom,
          label: "Scroll all the way down",
        },
      ],
      moving_a_card: [
        {
          keys: %w[enter space],
          hotkeys: %w[Enter Space],
          id: :card_move_start,
          label: "Start moving the focused card",
        },
        {
          keys: ["escape"],
          hotkeys: ["Escape"],
          id: :card_move_cancel,
          label: "Cancel the move in progress",
        },
        {
          keys: ["enter"],
          hotkeys: ["Enter"],
          id: :card_move_confirm,
          label: "Complete the move in progress",
        },
        {
          keys: ["↓", "j"],
          hotkeys: %w[ArrowDown j],
          id: :card_move_down,
          label: "Move card down",
        },
        {
          keys: ["ctrl ↓", "ctrl j"],
          hotkeys: %w[Mod+ArrowDown Mod+j],
          id: :card_move_bottom,
          label: "Move card to the bottom of the column",
        },
        {
          keys: ["↑", "k"],
          hotkeys: %w[ArrowUp k],
          id: :card_move_up,
          label: "Move card up",
        },
        {
          keys: ["ctrl ↑", "ctrl k"],
          hotkeys: %w[Mod+ArrowUp Mod+k],
          id: :card_move_top,
          label: "Move card to the top of the column",
        },
        {
          keys: ["←", "h"],
          hotkeys: %w[ArrowLeft h],
          id: :card_move_left_bottom,
          label: "Move card to the bottom of the column on the left",
        },
        {
          keys: ["shift ←", "shift h"],
          hotkeys: %w[Shift+ArrowLeft Shift+H],
          id: :card_move_left_top,
          label: "Move card to the top of the column on the left",
        },
        {
          keys: ["ctrl ←", "ctrl h"],
          hotkeys: %w[Mod+ArrowLeft Mod+h],
          id: :card_move_leftmost_bottom,
          label: "Move card to the bottom of the leftmost column",
        },
        {
          keys: ["ctrl shift ←", "ctrl shift h"],
          hotkeys: %w[Mod+Shift+ArrowLeft Mod+Shift+H],
          id: :card_move_leftmost_top,
          label: "Move card to the top of the leftmost column",
        },
        {
          keys: ["→", "l"],
          hotkeys: %w[ArrowRight l],
          id: :card_move_right_bottom,
          label: "Move card to the bottom of the column on the right",
        },
        {
          keys: ["shift →", "shift l"],
          hotkeys: %w[Shift+ArrowRight Shift+L],
          id: :card_move_right_top,
          label: "Move card to the top of the column on the right",
        },
        {
          keys: ["ctrl →", "ctrl l"],
          hotkeys: %w[Mod+ArrowRight Mod+l],
          id: :card_move_rightmost_bottom,
          label: "Move card to the bottom of the rightmost column",
        },
        {
          keys: ["ctrl shift →", "ctrl shift l"],
          hotkeys: %w[Mod+Shift+ArrowRight Mod+Shift+L],
          id: :card_move_rightmost_top,
          label: "Move card to the top of the rightmost column",
        },
      ],
      checks: [
        {
          keys: ["c"],
          hotkeys: ["c"],
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
          hotkeys: ["Shift+T"],
          id: :timestamps_toggle,
          label: "Toggle timestamps in logs",
        },
        {
          keys: ["shift f"],
          hotkeys: ["Shift+F"],
          id: :fullscreen_logs_toggle,
          label: "Toggle fullscreen logs",
        },
        {
          keys: ["esc"],
          hotkeys: ["Escape"],
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
          hotkeys: ["Mod+k"],
          id: :command_palette_open,
          label: "Open command palette",
        },
        {
          keys: ["ctrl /"],
          hotkeys: ["Mod+/"],
          id: :filter_field_focus,
          label: "Focus filter field",
        },
        {
          keys: ["←", "shift tab"],
          hotkeys: %w[ArrowLeft Shift+Tab],
          id: :cell_focus_left,
          label: "Move cell focus to the left",
        },
        {
          keys: ["→", "tab"],
          hotkeys: %w[ArrowRight Tab],
          id: :cell_focus_right,
          label: "Move cell focus to the right",
        },
        {
          keys: ["↑"],
          hotkeys: ["ArrowUp"],
          id: :cell_focus_up,
          label: "Move cell focus up",
        },
        {
          keys: ["↓"],
          hotkeys: ["ArrowDown"],
          id: :cell_focus_down,
          label: "Move cell focus down",
        },
        {
          keys: ["ctrl f6"],
          hotkeys: ["Mod+F6"],
          id: :focus_side_panel,
          label: "Move focus to/from side panel"
        },
      ],
      tasklist_block_navigation: [
        {
          keys: ["↑"],
          hotkeys: ["ArrowUp"],
          id: :tasklist_item_focus_up,
          label: "Move Tasklist Item focus up",
        },
        {
          keys: ["↓"],
          hotkeys: ["ArrowDown"],
          id: :tasklist_item_focus_down,
          label: "Move Tasklist Item focus down",
        },
        {
          keys: ["shift tab"],
          hotkeys: ["Shift+Tab"],
          id: :taklist_item_focus_left,
          label: "Move item menu focus focus to the left",
        },
        {
          keys: ["tab"],
          hotkeys: ["Tab"],
          id: :taklist_item_focus_right,
          label: "Move item menu focus focus to the right",
        },
        {
          keys: ["esc"],
          hotkeys: ["Escape"],
          id: :tasklist_item_focus_cancel,
          label: "Cancel focus for the tasklist items contents",
        },
        {
          keys: ["space"],
          hotkeys: ["Space"],
          id: :tasklist_item_focus_contents,
          label: "Focus into the tasklist item contents",
        },
        {
          keys: ["home"],
          hotkeys: ["Home"],
          id: :tasklist_item_focus_first,
          label: "Move tasklist item focus to the first item in the list",
        },
        {
          keys: ["end"],
          hotkeys: ["End"],
          id: :tasklist_item_focus_last,
          label: "Move tasklist item focus to the last item in the list",
        },
      ],
      memex_table_manipulation: [
        {
          keys: ["enter"],
          hotkeys: ["Enter"],
          id: :cell_edit_start,
          label: "Toggle edit mode for the focused cell",
        },
        {
          keys: ["esc"],
          hotkeys: ["Escape"],
          id: :cell_edit_cancel,
          label: "Cancel editing for the focused cell",
        },
        {
          keys: ["ctrl d"],
          hotkeys: ["Mod+d"],
          label: "Fill selected cells down",
        },
        {
          keys: ["ctrl shift \\"],
          hotkeys: ["Mod+Shift+\\"],
          id: :action_menu_open,
          label: "Open row actions menu",
        },
        {
          keys: ["shift space"],
          hotkeys: ["Shift+Space"],
          label: "Select item",
        },
        {
          keys: ["space"],
          hotkeys: ["Space"],
          id: :open_selected_item,
          label: "Open selected item"
        },
        {
          keys: ["e"],
          hotkeys: ["e"],
          id: :archive,
          label: "Archive items",
        }
      ]
    }.freeze

  DEFAULT_KEYBOARD_SHORTCUTS_TITLES = \
    {
      notifications_v2: "Notifications",
      repositories: "Repositories",
      code_editor: "Code editor",
      source_code: "Source code browsing",
      file_tree: "File tree",
      issues: "Issues",
      commits: "Browsing commits",
      commit_list: "Commit list",
      dashboards: "Dashboards",
      notifications: "Notifications",
      pull_request_list: "Pull request list",
      pull_request_conversation: "Pull request - Conversation tab",
      pull_request_files_changed:  "Pull request - Files changed tab",
      project_cards: "Project card shortcuts",
      moving_a_card: "Moving a card",
      moving_columns: "Moving a column",
      network_graph: "Network graph",
      checks: "Checks",
      memex_table_navigation: "Navigating a Project",
      memex_table_manipulation: "Manipulating a Project",
      actions: "Actions",
      global: "Site-wide shortcuts"
    }.freeze
end
