# typed: true
# frozen_string_literal: true

class Branch::CreateBranchComponent < ApplicationComponent

  # create_url: nil
  #   the url used by the branch creation form
  # target_repositories_url: nil,
  #   the url to populate the "Repository Destination" dropdown
  # repository: nil,
  #   the current repository
  # title: "Create a branch",
  #   the title shown in
  # default_new_branch_name: "",
  #   the default value of the branch name input
  # hide_whats_next: false,
  #   hides the "What's Next?" section, by default it is shown
  # hide_change_branch_source: false,
  #   hides the "Change branch source" link, which makes the "Branch source" dropdown inaccessible,
  #   shown by default
  # hide_repository_destination: false,
  #   hides the "Repository Destination" dropdown, shown by default
  # feedback_url: nil,
  #   a url for the "(Beta) Share feedback" link, blank and hidden by default
  # show_branch_source: false
  #   shows the "Branch source" dropdown, and hides the "Change branch source" link,
  #   acting as if the user immediately clicked the "Change branch source" link, hidden by default
  # show_fork_source: false
  #   shows the upstream and current repository as options in "Branch source", hidden by default
  def initialize(
    create_url: nil,
    target_repositories_url: nil,
    repository: nil,
    title: "Create a branch",
    default_new_branch_name: "",
    hide_whats_next: false,
    hide_change_branch_source: false,
    hide_repository_destination: false,
    feedback_url: nil,
    show_branch_source: false,
    show_fork_source: false
  )
    @create_url = create_url
    @target_repositories_url = target_repositories_url
    @repository = repository
    @title = title
    @default_new_branch_name = default_new_branch_name
    @hide_whats_next = hide_whats_next
    @hide_change_branch_source = hide_change_branch_source
    @hide_repository_destination = hide_repository_destination
    @feedback_url = feedback_url
    @show_branch_source = show_branch_source
    @show_fork_source = show_fork_source
  end

  def create_url
    @create_url
  end

  def target_repositories_url
    @target_repositories_url
  end

  def repository
    @repository
  end

  def title
    @title
  end

  def repository_nwo
    @repository.name_with_display_owner
  end

  def repository_default_branch
    @repository.default_branch
  end

  def default_new_branch_name
    @default_new_branch_name
  end

  def hide_whats_next?
    @hide_whats_next
  end

  def hide_change_branch_source?
    @hide_change_branch_source
  end

  def hide_repository_destination?
    @hide_repository_destination
  end

  def feedback_url
    @feedback_url
  end

  def show_branch_source?
    @show_branch_source
  end

  def show_fork_source?
    @show_fork_source
  end
end
