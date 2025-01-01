# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class SuggestionsController < ApplicationController
  include OcticonsHelper
  include TextHelper

  before_action :login_required
  before_action :enforce_required_parameters
  before_action :load_legacy_params
  before_action :repo_access_required
  before_action :require_xhr

  rescue_from ConditionalAccess::Enforcer::ResourceError, with: :no_resource

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Memex,
    only: [:show]

  def show
    suggester = suggester_for(suggestion_subject, query: params.fetch(:q, ""))
    return render_404 unless suggester

    respond_to do |format|
      format.json do
        if params[:issue_suggester].present?
          suggestions = if current_repository&.discussions_active?
            suggester.issues_and_discussions
          else
            suggester.issues
          end

          output_suggestions = suggestions.map do |elem|
            type = if elem.respond_to?(:pull_request_id?)
              if elem.pull_request_id?
                "pull_request"
              elsif elem.respond_to?(:closed_at?)
                if elem.closed_at?
                  if elem.state_reason_not_planned? || elem.state_reason_duplicate?
                    "skip"
                  else
                    "issue_closed"
                  end
                else
                  "issue_open"
                end
              end
            else
              elem.closed? ? "discussion_#{elem.state_reason}" : "discussion"
            end
            title = title_markdown(elem.title)

            { id: elem.id, number: elem.number, title: title, type: type }
          end

          not_planned_icon_info = Issue::StateReasonDependency::OCTICONS[:not_planned]

          icons = {
            pull_request: octicon("git-pull-request"),
            pull_request_closed: octicon("git-pull-request-closed"),
            pull_request_draft: octicon("git-pull-request-draft"),
            issue_open: octicon("issue-opened", class: "open"),
            issue_closed: octicon("issue-closed", class: "closed"),
            skip: octicon(not_planned_icon_info[:icon], class: not_planned_icon_info[:class]),
            discussion: octicon("comment-discussion"),
          }

          Closables::BaseComponent::DISCUSSION_REASONS.each do |reason|
            icons[:"discussion_#{reason.value}"] = octicon(reason.octicon, class: "color-fg-#{reason.octicon_color}")
          end

          render json: {
            suggestions: output_suggestions,
            icons: icons,
          }
        elsif params[:mention_suggester].present?
          render json: suggester.mentions
        else
          head 400
        end
      end
    end
  end

  private

  def resource_for_conditional_access
    suggestion_subject
  end

  def target_for_conditional_access
    suggestion_subject.target_for_conditional_access
  end

  def no_resource
    render_404
  end

  # Bridge new GraphQL Relay ID into old Suggester interface which accepts a
  # subject type and database id.
  def load_legacy_params
    return unless params[:global_id]
    return unless suggestion_subject

    # Ideally Suggester doesn't depend on a repository parameter altogether
    @current_repository = suggestion_subject.try(:repository)
    @owner = current_repository.owner if current_repository
    params[:user_id] ||= owner&.id
  end

  POSSIBLE_SUBJECT_TYPES = [
    Platform::Objects::CommitComment,
    Platform::Objects::Discussion,
    Platform::Objects::Issue,
    Platform::Objects::IssueComment,
    Platform::Objects::Organization,
    Platform::Objects::PullRequest,
    Platform::Objects::PullRequestReview,
    Platform::Objects::PullRequestReviewComment,
    Platform::Objects::Team,
    Platform::Objects::TeamDiscussion,
    Platform::Objects::TeamDiscussionComment,
  ].freeze

  def suggestion_subject # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @suggestion_subject if defined?(@suggestion_subject)
    @suggestion_subject = if params[:global_id]
      find_subject_by_global_id
    else
      find_subject_by_type
    end
  end

  # Creates the suggester instance for the subject. Passes a query string to the suggester if one is supported.
  #
  # NOTE: When adding to the list below, consider writing a new controller to
  # provide suggestions for your type instead. There isn't much reusable code
  # in this controller. The reuse is in the suggester model classes.
  #
  # Returns nil if no appropriate suggester can be created.
  def suggester_for(subject, query: "")
    get_avatars = params[:user_avatar] == "1"
    case subject
    when CommitComment
      Suggester::RepositorySuggester.new(viewer: current_user, subject: subject.commit, cap_filter: cap_filter, query: query, get_avatars: get_avatars)
    when Commit, Issue, PullRequest, Repository, Discussion
      Suggester::RepositorySuggester.new(viewer: current_user, subject: subject, cap_filter: cap_filter, query: query, get_avatars: get_avatars)
    when PullRequestReview
      Suggester::RepositorySuggester.new(viewer: current_user, subject: subject.pull_request, cap_filter: cap_filter, query: query, get_avatars: get_avatars)
    when IssueComment
      if subject.issue&.pull_request?
        Suggester::RepositorySuggester.new(viewer: current_user, subject: subject.issue&.pull_request, cap_filter: cap_filter, query: query, get_avatars: get_avatars)
      else
        Suggester::RepositorySuggester.new(viewer: current_user, subject: subject.issue, cap_filter: cap_filter, query: query, get_avatars: get_avatars)
      end
    when DiscussionPost, DiscussionPostReply
      Suggester::TeamSuggester.new(viewer: current_user, team: subject.team, cap_filter: cap_filter)
    when Organization
      Suggester::OrganizationMemberSuggester.new(viewer: current_user, org: subject, cap_filter: cap_filter)
    when Team
      Suggester::TeamSuggester.new(viewer: current_user, team: subject, cap_filter: cap_filter)
    end
  end

  def find_subject_by_global_id
    typed_object_from_id(POSSIBLE_SUBJECT_TYPES, params[:global_id])
  rescue Platform::Errors::NotFound
    nil
  end

  # Finds the suggester's subject for the subject_type + subject_id pair. Both
  # parameters are optional so default to the current repository as a subject
  # if they are missing.
  #
  # Returns an Issue, PullRequest, Commit, Repository, Discussion, Organization or nil.
  def find_subject_by_type
    # projects dont require current_repository everything else does
    return if GitHub.flipper[:return_unless_current_repository].enabled? && !current_repository && params[:subject_type] != "project"

    id = params[:subject_id]

    case params[:subject_type]
    when "issue"
      id ? current_repository.issues.find_by_id(id) : current_repository # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    when "pull_request"
      id ? current_repository.pull_requests.find_by_id(id) : current_repository
    when "commit"
      begin
        current_repository.commits.find(id)
      rescue RepositoryObjectsCollection::InvalidObjectId
        nil
      end
    when "discussion"
      id ? current_repository.discussions.find_by_id(id) : current_repository
    when "project"
      if id
        # "project" subject type is only supported for organization owned projects
        project = MemexProject.find_by(id: id)
        project.owner if project && project.owner.is_a?(Organization)
      end
    else
      current_repository
    end
  end

  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    @current_repository = resolve_repository_and_owner[:repository]
  end

  # TODO Remove user_id parameter and owner method. Only a repository_id
  # parameter is needed since owner can be retrieved from it. Another option
  # is to change the route to /:owner/:repo/suggestions to make the data
  # dependency explict.
  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @owner if defined?(@owner)
    @owner = resolve_repository_and_owner[:owner]
  end

  # Since there are 2 ways to get the repository and owner, we need to resolve them in a separate
  # function so we don't end up with a circular dependency.
  def resolve_repository_and_owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @repository_and_owner if defined?(@repository_and_owner)
    @repository_and_owner = if params[:repository].present? && params[:user_id].present?
      retrieved_owner = User.find_by_login(params[:user_id])
      repo = retrieved_owner.find_repo_by_name(params[:repository]) if retrieved_owner
      { repository: repo, owner: retrieved_owner }
    elsif params[:repository_id].present?
      repo = Repository.find_by(id: params[:repository_id])
      { repository: repo, owner: repo&.owner }
    else
      {}
    end
  end

  def login_required
    render_404 unless logged_in?
  end

  # Documents the combinations of parameters we need. This can be removed if
  # we move the global_id code path to a separate controller.
  def enforce_required_parameters
    return if params[:global_id].present?
    return if params[:subject_type].present?
    return if params[:subject_type].blank? && params[:subject_id].blank?
    head 400
  end

  def repo_access_required
    return unless params[:user_id].present? || params[:repository_id].present? # if we can resolve a user, we need to check for repo access
    return render_404 unless owner
    return render_404 unless current_repository
    return render_404 unless current_repository.public? || current_repository.pullable_by?(current_user)
    render_404 unless required_external_identity_session_present?(target: owner)
  end
end
