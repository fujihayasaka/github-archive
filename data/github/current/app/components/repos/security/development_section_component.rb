# typed: strict
# frozen_string_literal: true

class Repos::Security::DevelopmentSectionComponent < ApplicationComponent

  sig { returns(T::Array[CodeScanning::AlertLink]) }
  attr_reader :alert_links

  sig do
    params(repository: Repository,
      alert_number: Integer,
      alert_title: String,
      alert_links: T::Array[CodeScanning::AlertLink],
      is_alert_closed: T::Boolean,
      suggested_fix: T.nilable(Turboscan::Proto::SuggestedFix),
      system_arguments: T.untyped).void
  end
  def initialize(
    repository:,
    alert_number:,
    alert_title:,
    alert_links:,
    is_alert_closed: false,
    suggested_fix: nil,
    **system_arguments
  )
    @repository = repository
    @suggested_fix = suggested_fix
    @alert_number = alert_number
    @alert_title = alert_title
    @alert_links = alert_links
    @is_alert_closed = is_alert_closed
    @system_arguments = system_arguments
  end

  sig { returns(T::Boolean) }
  def suggested_fix?
    @suggested_fix.present?
  end

  sig { returns(T::Boolean) }
  def pushable_by_current_user?
    @repository.pushable_by?(current_user)
  end

  sig { returns(T::Boolean) }
  def alert_open?
    !@is_alert_closed
  end

  sig { returns(T::Boolean) }
  def disabled_create_branch_button?
    !pushable_by_current_user?
  end

  sig { returns(T::Boolean) }
  def user_can_edit_alert_links?
    # TODO is this the permission we want to use?
    # if we don;t match the same thing we use for allowing creating a branch
    # (which also creates an alert link) then we should use sth that is
    # at least as restrictive, so another option would be
    # @repository/writable_by?(current_user)
    # do we want to allow creation of alert links after the alert has been fixed?
    pushable_by_current_user?
  end

  sig { returns(T::Boolean) }
  def alert_links?
    alert_links.present?
  end

  sig { params(alert_link: CodeScanning::AlertLink).returns(T.nilable(String)) }
  def alert_link_url(alert_link)
    if alert_link.pull_request?
      gh_show_pull_request_path(alert_link.pull_request)
    else
      tree_path("", alert_link.branch&.name, @repository)
    end
  end

  sig { params(alert_link: CodeScanning::AlertLink).returns(T.nilable(String)) }
  def alert_link_title(alert_link)
    if alert_link.pull_request?
      T.must(alert_link.pull_request).title
    else
      alert_link.branch&.name_for_display
    end
  end

  sig { params(alert_link: CodeScanning::AlertLink).returns(T.nilable(String)) }
  def alert_link_subtitle(alert_link)
    pr = alert_link.pull_request
    branch = alert_link.branch

    if pr.present?
      branch_link = render(Primer::Beta::Link.new(
        href: tree_path("", pr.base_ref_name, @repository),
        target: "_blank")
      ) { pr.base_ref_name }

      case pr.state
      when :open
        content_tag(:span, "##{pr.number} opened #{time_ago_in_words(pr.created_at)} ago merges into ") +
          branch_link
      when :closed
        "##{pr.number} was closed #{time_ago_in_words(pr.closed_at)}"
      when :merged
        content_tag(:span, "##{pr.number} was merged into ") +
          branch_link +
          content_tag(:span, " #{time_ago_in_words(pr.merged_at)} ago")
      end
    elsif branch.present?
      "Updated #{time_ago_in_words(branch.last_modified_at)} ago"
    end
  end

  sig { params(alert_link: CodeScanning::AlertLink).returns({ icon: Symbol, color: Symbol }) }
  def alert_link_icon(alert_link)
    pr = alert_link.pull_request
    return { icon: :"git-branch", color: :default } if pr.blank?

    case pr.state
    when :merged
      { icon: :"git-merge", color: :done }
    when :open
      pr.draft? ? { icon: :"git-pull-request-draft", color: :default } : { icon: :"git-pull-request", color: :open }
    when :closed
      { icon: :"git-pull-request-closed", color: :closed }
    else
      { icon: :"git-pull-request", color: :default }
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def create_branch_dialog_props
    alert_number_with_suggested_fixes = @suggested_fix.present? ? [@alert_number] : []
    {
      alertNumbers: [@alert_number],
      alertNumbersWithSuggestedFixes: alert_number_with_suggested_fixes,
      firstAlertWithSuggestedFixTitle: @alert_title,
      repository: {
        name: @repository.name,
        ownerLogin: @repository.owner&.display_login,
        path: @repository.path,
        typeIcon: @repository.repo_type_icon
      },
      createPath: create_code_scanning_branch_path(repository: @repository, user_id: @repository.owner, number: @alert_number),
      someSelectedAlertsAreClosed: @is_alert_closed,
      isCampaign: false
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def development_picker_props
    linked_branches = []
    linked_pull_requests = []
    alert_links.each do |alert_link|
      if alert_link.pull_request?
        linked_pull_requests << convert_to_pull_request_picker_props(T.must(alert_link.pull_request))
      else
        linked_branches << convert_to_branch_picker_props(T.must(alert_link.branch))
      end
    end

    {
      repositoryNwo: @repository.name_with_display_owner,
      repositoryId: @repository.id,
      alertNumber: @alert_number,
      linkedBranches: linked_branches,
      linkedPullRequests: linked_pull_requests,
      isCreateBranchDialogOpen: false,
      prAndBranchPickerSubtitle: "search for pull requests and branches to link",
      updateAlertLinksPath: update_code_scanning_alert_links_path(repository: @repository, user_id: @repository.owner, number: @alert_number),
      triggerOpen?: true
    }
  end

  sig { params(pull_request: PullRequest).returns(T::Hash[Symbol, T.untyped]) }
  def convert_to_pull_request_picker_props(pull_request)
    {
      __typename: "PullRequest",
      createdAt: pull_request.created_at,
      id: pull_request.global_relay_id,
      isDraft: pull_request.draft?,
      isInMergeQueue: pull_request.in_merge_queue?,
      number: pull_request.number,
      repository: {
        id: @repository.id,
        nameWithOwner: @repository.name_with_display_owner,
      },
      state: "#{pull_request.state}".upcase,
      title: pull_request.title,
      url: pull_request.url,
    }
  end

  sig { params(branch: Git::Ref).returns(T::Hash[Symbol, T.untyped]) }
  def convert_to_branch_picker_props(branch)
    {
      __typename: "Ref",
      associatedPullRequests: {
        # we know there are 0 PRs associated to the branch because otherwise
        # we would have migrated the alert link to point to the PR.
        totalCount: 0
      },
      id: branch.global_relay_id,
      name: branch.name,
      repository: {
        id: @repository.id,
        nameWithOwner: @repository.name_with_display_owner,
      },
    }
  end
end
