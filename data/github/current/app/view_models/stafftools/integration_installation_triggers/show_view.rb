# typed: true
# frozen_string_literal: true

class Stafftools::IntegrationInstallationTriggers::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :trigger

  ELLIPSIS = ".../"
  MAX_PATH_LENGTH = 50 - ELLIPSIS.length

  HUMAN_READABLE_TRIGGER_TYPES = {
    user_created: "a user or organization is created",
    file_added: ["a file is added at '%{display_path}'", [:display_path]],
    team_sync_enabled: "a user enabled Team Sync for an organization",
    dependency_graph_initialized: "a user enrolls in our dependency analysis service",
    dependency_update_requested: "a user requests a dependency update from Dependabot",
    page_build: "a GitHub Pages build is started",
    automatic_security_updates_initialized: "a user enables the Automatic Security Updates feature",
    pending_dependabot_installation_requested: "an internal developer kicks off Dependabot mass installations",
    button_clicked: "a given button is clicked",
    oauth_code_exchanged: "an oauth code is exchanged for an access token",
    dependabot_repository_access_updated: "a user updates the set of repositories accessible to Dependabot",
    dependabot_jit_access_requested: "Dependabot obtains on-demand access to a repository",
    actions_automatic_installation: "Actions automatically installed",
  }

  delegate :integration, :install_type, :path, to: :trigger

  def display_path
    if show_tooltip?
      last = File.basename(trigger.path)
      path_without_filename = File.dirname(trigger.path)

      truncated_path = path_without_filename[0...MAX_PATH_LENGTH - last.length]

      "#{truncated_path}#{ELLIPSIS}#{last}"
    else
      trigger.path
    end
  end

  def show_tooltip?
    return false unless trigger.path
    trigger.path.length > MAX_PATH_LENGTH
  end

  def install_type_explanation
    string, attrs = HUMAN_READABLE_TRIGGER_TYPES[install_type.to_sym]
    return string if attrs.nil?

    attrs = attrs.each_with_object({}) { |attr, hash| hash[attr] = public_send(attr) }
    sprintf(string, attrs)
  end
end
