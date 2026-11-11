# typed: strict
# frozen_string_literal: true

class Repos::Security::DevelopmentSectionComponent < ApplicationComponent

  sig do
    params(repository: Repository,
      alert_number: Integer,
      alert_title: String,
      linked_branches: T::Array[T::Hash[Symbol, T.untyped]],
      linked_pull_requests: T::Array[T::Hash[Symbol, T.untyped]],
      branch_list_cache_key: String,
      is_alert_closed: T::Boolean,
      suggested_fix: T.nilable(Turboscan::Proto::SuggestedFix),
      system_arguments: T.untyped).void
  end
  def initialize(
    repository:,
    alert_number:,
    alert_title:,
    linked_branches:,
    linked_pull_requests:,
    branch_list_cache_key:,
    is_alert_closed: false,
    suggested_fix: nil,
    **system_arguments
  )
    @repository = repository
    @suggested_fix = suggested_fix
    @alert_number = alert_number
    @alert_title = alert_title
    @linked_branches = linked_branches
    @linked_pull_requests = linked_pull_requests
    @branch_list_cache_key = branch_list_cache_key
    @is_alert_closed = is_alert_closed
    @system_arguments = system_arguments
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def development_section_props
    create_branch_path = suggested_fix? ? repository_code_scanning_autofix_commits_path(@repository.owner, @repository, @alert_number) : create_code_scanning_branch_path(repository: @repository, user_id: @repository.owner, number: @alert_number)

    {
      alertNumber: @alert_number,
      createBranchPath: create_branch_path,
      isAlertClosed: @is_alert_closed,
      alertTitle: @alert_title,
      hasSuggestedFix: suggested_fix?,
      isCreateBranchDialogOpen: false,
      linkedBranches: @linked_branches,
      linkedPullRequests: @linked_pull_requests,
      prAndBranchPickerSubtitle: "search for pull requests and branches to link",
      pushableByUser: pushable_by_current_user?,
      repository: {
        id: @repository.id,
        name: @repository.name,
        ownerLogin: @repository.owner&.display_login,
        path: @repository.path,
        defaultBranch: @repository.default_branch,
      },
      branchListCacheKey: @branch_list_cache_key,
      updateAlertLinksPath: update_code_scanning_alert_links_path(repository: @repository, user_id: @repository.owner, number: @alert_number),
      linkableItemsSearchPath: repository_code_scanning_linkable_search_path(repository: @repository, user_id: @repository.owner, number: @alert_number),
    }
  end

  private

  sig { returns(T::Boolean) }
  def suggested_fix?
    @suggested_fix.present?
  end

  sig { returns(T::Boolean) }
  def pushable_by_current_user?
    @repository.pushable_by?(current_user)
  end
end
