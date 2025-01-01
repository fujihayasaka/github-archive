# typed: true
# frozen_string_literal: true

class Codespaces::DropdownListComponent < ApplicationComponent
  include ResilienceHelper
  include CodespacesHelper

  attr_reader :query, :event_target, :pr_dropdown, :codespaces_by_branch,
              :user_settings, :show_actions, :current_branch, :missing_head_repo, :missing_head_ref, :available_skus, :codespaces

  delegate :build_codespace, :repository, :ref, :pull_request, :codespaces_context, :at_limit?, :repository_policy, :default_sku, :codespace_limit, to: :query
  alias_method :codespace, :build_codespace

  # Include attributes here that need to carry over each time this component reloads from the controller request
  CODESPACES_LIST_QUERY_PARAMS = %i(
    missing_head_ref
    current_branch
    event_target
    pr_dropdown
    show_actions
  )

  # query                         - The Codespaces::Query used to populate the list
  # event_target                  - The event target that should be passed to hydro (optional, default: "")
  # pr_dropdown                   - A boolean, used to render this component differently if in the context of a PR dropdown (optional, default: false)
  # current_branch                - The branch name in the current context
  # missing_head_repo             - A boolean, indicating a PR's head repository is missing (likely deleted)
  # missing_head_ref              - A boolean, indicating a PR's head ref is missing from the repository (likely deleted branch)
  # available_skus                - A list of available SKUs for the user and repository

  def initialize(
    query:,
    event_target: "",
    pr_dropdown: false,
    user_settings: nil,
    show_actions: true,
    current_branch: nil,
    missing_head_repo: false,
    missing_head_ref: false,
    available_skus: []
  )
    @query = query
    @event_target = event_target
    @pr_dropdown = pr_dropdown
    @user_settings = user_settings
    @show_actions = show_actions
    @current_branch = current_branch
    @missing_head_repo = missing_head_repo
    @missing_head_ref = missing_head_ref
    @available_skus = available_skus
  end

  def before_render
    @codespaces = @query.codespaces

    # If the head repo is missing, the @query is pointed at the PR base repo,
    # it would be a confusing difference in behavior if we displayed those codespaces here.
    return if missing_head_repo

    @codespaces_by_branch = if current_branch
      on_current_branch, others = @codespaces.sort_by(&:last_used_at).reverse.partition do |cs|
        cs.repository == @query.repository && cs.display_branch == current_branch
      end
      { current_branch: on_current_branch, other_branches: others }
    elsif @codespaces.any?
      # We have a `current_branch` in most cases, but one case that gets here is a detached HEAD.
      # For example, try creating from https://github.com/github/github/tree/f6ac7e821eb6259d9744005a780e789d58caddc1
      { current_branch: [], other_branches: @codespaces.sort_by(&:last_used_at).reverse }
    else
      {}
    end

    @codespaces_by_branch[:other_branches]&.sort! { |cs| cs.repository == @query.repository ? 0 : 1 } # Put forks at the bottom
  end

  def data_src
    codespace_param = {}
    codespace_param[:ref] = query.ref if query.ref
    codespace_param[:pull_request_id] = query.pull_request_id if query.pull_request_id

    codespaces_path({
      repo: query.repository.id,
      codespace: codespace_param,
    }.merge(src_query_params))
  end

  memoize def is_spoofed_commit?
    return false unless codespace

    with_database_error_fallback(fallback: true) do
      # Disable create button on spoofed commits: https://github.com/github/codespaces/issues/8606
      if codespace.ref.blank? || codespace.ref == codespace.repository.default_branch || codespace.repository.refs.find(codespace.ref)
        # If we're not creating from a ref or we're on the default branch (or another existing branch) we don't need to worry about spoofing.
        false
      else
        begin
          git_ref = Codespaces::GetTargetRef.call(repository: codespace.repository, name_or_oid: codespace.ref)
          # If we can't find this git ref then we'll just assume this is spoofed otherwise check if we have any branches
          # with that oid.
          # This check was essentially pulled from the checks we do in `app/view_models/commits/branch_list_view.rb` to
          # determine whether or not to show the spoofed_commit_warning partial.
          !git_ref&.sha || codespace.repository.rpc.branch_contains(git_ref.sha).empty?
        rescue GitRPC::ObjectMissing
          true
        end
      end
    end
  rescue GitHub::Spokes::ClientError
    false
  end

  def delete_confirmation_message(codespace)
    if codespace.has_unpushed_changes?
      "#{codespace.safe_display_name} has unpushed changes, are you sure you want to delete?"
    else
      "Are you sure you want to delete #{codespace.safe_display_name}?"
    end
  end

  # We should show the empty state when:
  # - There are no codespaces
  # - There are no codespaces by branch because missing_head_repo is true
  def show_empty_state?
    codespaces.empty? || !codespaces_by_branch.present?
  end

  def needs_fork_to_push?(codespace)
    if codespace.repository_id == query.repository.id
      # This codespace is directly associated with the repo we're viewing the dropdown for.
      repository_policy.read_only_and_forkable?
    elsif codespace.repository_id == query.repository.parent_id
      # Viewing the dropdown for a fork, but this codespace is from the parent.
      query.repository_policy(repository: codespace.repository).read_only_and_forkable?
    else
      false
    end
  end

  memoize def is_at_limit?
    at_limit?(build_codespace.billable_owner)
  end

  private

  # returns hash of attrs to include in query params
  # ie: { event_target: event_target, pr_dropdown: pr_dropdown ... etc }
  def src_query_params
    CODESPACES_LIST_QUERY_PARAMS.reduce({}) do |params, attr|
      value = self.send(attr)
      params[attr] = value unless value.nil? # only assign if value is set
      params
    end
  end
end
