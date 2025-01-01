# typed: true
# frozen_string_literal: true

# patch to, https://github.com/github-community-projects/graphql-client/blob/925e3c7deab395f417d49a6c156d25d8e2d5c48e/lib/graphql/client/view_module.rb#L46-L59
# This prevents processing all views looking for "<%graphql" in their contents which takes a lot of time.
# Since we don't add graphql to new views, this list should only go out of date when graphql is removed.
module ViewModulePatch
  extend T::Helpers

  requires_ancestor do
    Module
  end

  requires_ancestor do
    GraphQL::Client::ViewModule
  end

  ALLOWED_GRAPHQL_PATHS = [
    "app/views/comments/projects/_comment_header_reaction_button.html.erb",
    "app/views/comments/projects/_edit_form.html.erb",
    "app/views/comments/projects/edit/_tabnav.html.erb",
    "app/views/comments/projects/edit/_write_content.html.erb",
    "app/views/issues/events/_project_events.html.erb",
    "app/views/orgs/team_projects/_add_project_dialog.html.erb",
    "app/views/orgs/team_projects/_container.html.erb",
    "app/views/orgs/team_projects/_list.html.erb",
    "app/views/orgs/team_projects/_project.html.erb",
    "app/views/orgs/team_projects/_suggestions.html.erb",
    "app/views/orgs/team_projects/index.html.erb",
    "app/views/project_columns/_add.html.erb",
    "app/views/project_columns/_menu.html.erb",
    "app/views/project_columns/_project_column.html.erb",
    "app/views/project_workflows/_edit.html.erb",
    "app/views/project_workflows/_form.html.erb",
    "app/views/project_workflows/_presets.html.erb",
    "app/views/projects/_add_cards_link.html.erb",
    "app/views/projects/_change_state.html.erb",
    "app/views/projects/_column_nav.html.erb",
    "app/views/projects/_fullscreen_header.html.erb",
    "app/views/projects/_header.html.erb",
    "app/views/projects/_linked_repositories_list.html.erb",
    "app/views/projects/_list.html.erb",
    "app/views/projects/_project_progress.html.erb",
    "app/views/projects/_show_progress.html.erb",
    "app/views/projects/index.html.erb",
    "app/views/projects/modals/_clone.html.erb",
    "app/views/projects/panes/_add_cards.html.erb",
    "app/views/projects/panes/_metadata.html.erb",
    "app/views/projects/show.html.erb",
    "app/views/users/tabs/_projects.html.erb",
  ].map do |path|
    File.join(Rails.root, path)
  end

  def eager_load!
    return unless File.directory?(load_path)

    Dir.entries(load_path).sort.each do |entry|
      full_path = File.join(load_path, entry)
      if entry == "." || entry == ".." || (!ALLOWED_GRAPHQL_PATHS.find { |allowed_path| allowed_path.start_with?(full_path) })
        next
      end
      name = entry.sub(/(\.\w+)+$/, "").camelize.to_sym
      if GraphQL::Client::ViewModule.valid_constant_name?(name)
        mod = const_defined?(name, false) ? const_get(name) : load_and_set_module(name)
        mod.eager_load! if mod
      end
    end

    nil
  end
end
