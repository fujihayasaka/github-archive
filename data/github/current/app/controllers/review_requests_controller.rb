# typed: true
# frozen_string_literal: true

class ReviewRequestsController < AbstractRepositoryController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:menu]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:menu],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:team_size_check]

  MAX_TEAM_SIZE_BEFORE_CONFIRMATION_REQUIRED = 100

  include GitHub::Memoizer
  include ShowPartial

  before_action :login_required
  before_action :writable_repository_required, except: %w[menu]

  # Request review for a pull request
  #
  # Expected params:
  #    :reviewer_user_ids - The User ids to request review from
  #    :reviewer_team_ids - The Team ids to request review from
  #    :suggested_reviewer_id - The id of the suggested reviewer
  #    :re_request_reviewer_id - The User id to re-request review from
  #
  # Creates new review requests
  # Updates the pull_request with the new reviewers ids.
  #
  # For AJAX requests, JSON is returned with the HTML of the infobar and
  # context pane partials.
  def create
    pull = PullRequest.with_number_and_repo(params[:id], current_repository)
    raise NotFound unless pull

    reviewers = if re_requesting_review?
      [re_requesting_review_from]
    else
      user_reviewers + team_reviewers
    end

    if exclude_stale_user_review_requests?
      partial_last_updated = Time.at(params[:partial_last_updated].to_i)
      # ignore any requests for reviews that have been fulfilled since partial_last_updated
      user_ids_recently_reviewed = pull.reviews.where("submitted_at > ?", partial_last_updated).where(user_id: reviewer_user_ids).pluck(:user_id)
      reviewers = reviewers.reject do |reviewer|
        next unless reviewer.is_a?(User)
        user_ids_recently_reviewed.include?(reviewer.id)
      end
    end

    unless pull.request_review_from(reviewers: reviewers, actor: current_user, re_request: re_requesting_review?, append: re_requesting_review?)
      return render_404
    end

    track_issue_edits_from_project_board(edited_fields: ["reviewers"])

    respond_to do |format|
      format.html do
        suggestions = show_suggestions?(pull) ? pull.suggested_reviewers(actor: current_user) : nil
        render partial: "pull_requests/sidebar/show/reviewers", locals: {
          pull_request: pull,
          suggested_reviewers: suggestions,
          deferred_content: false,
        }
      end
    end
  end

  def create_new # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?
    pull = build_pull
    return head 404 unless pull

    suggestions = show_suggestions?(pull) ? pull.suggested_reviewers(actor: current_user) : nil

    respond_to do |format|
      format.html do
        render partial: "issues/sidebar/new/reviewers", locals: {
          pull: pull,
          suggested_reviewers: suggestions,
          deferred_content: false,
        }
      end
    end
  end

  def team_size_check # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Teams::LargeTeamConfirmationDialogComponent.new(
          teams: team_reviewers.filter(&method(:require_confirmation?)),
          type: :review_request,
          threshold: MAX_TEAM_SIZE_BEFORE_CONFIRMATION_REQUIRED,
        ), layout: false
      end
    end
  end

  def re_request_review # rubocop:todo GitHub/UseRestfulActions
    pull = current_repository.issues.find_by_number(params[:id])&.pull_request
    reviewer = User.find(params[:reviewer_id])

    if pull.review_requested_for?(reviewer)
      return redirect_to pull_request_path(pull)
    end

    unless pull.request_review_from(reviewers: [reviewer], actor: current_user, re_request: true, append: true)
      return render_404
    end

    redirect_to pull_request_path(pull)
  end

  def menu # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    pull =
      if params[:id]
        current_repository.issues.find_by_number(params[:id])&.pull_request
      else
        build_pull
      end

    return head 404 unless pull
    return head 401 unless pull.can_request_review?(current_user)

    timer = Timer.start

    review_requests = pull.pending_review_requests

    type_ahead_enabled = params[:typeAhead].present?

    # If there is no type-ahead, we will set search_query to nil, which will force the 'default state' in the `sorted_reviewers` call below.
    search_query = nil
    if type_ahead_enabled
      search_query = params[:q].to_s
    end

    possible_reviewers = pull.sorted_reviewers(current_user, requests: review_requests, search_query: search_query).to_a.uniq

    copilot_code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    if copilot_code_review_access.can_create_review_request?
      reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
      possible_reviewers.unshift(reviewer_app.bot).uniq! unless reviewer_app.nil?
    end

    respond_to do |format|
      format.json do
        payload = {}
        # Adding this feature flag for large organizations that are seeing 5000ms+ load times when loading the reviewers menu.
        skip_suggestions = if pull.repository&.feature_enabled?(:skip_suggested_reviewers_by_repo) || pull.repository&.organization&.feature_enabled?(:skip_suggested_reviewers_by_repo)
          true
        else
          false
        end

        # If we have a valid search query, we can ignore suggestions.
        if (search_query.nil? || search_query.empty?) && !skip_suggestions && pull.include_reviewer_suggestions?(user: current_user)
          requested_teams = review_requests.teams
          reviewer_suggestions = pull.suggested_reviewers(requests: review_requests, teams: requested_teams, actor: current_user)

          # Don't show suggested users twice
          reviewer_suggestion_users = reviewer_suggestions.map(&:user)
          possible_reviewers -= reviewer_suggestion_users

          GitHub::PrefillAssociations.prefill_associations(reviewer_suggestion_users, { user_status: :organization })

          payload[:suggestions] = reviewer_suggestions.map do |suggestion|
            reviewer_json_payload(pull, suggestion.user).update(description: suggestion.description)
          end
        end

        possible_user_reviewers = possible_reviewers.select { |reviewer| reviewer.is_a?(User) }
        GitHub::PrefillAssociations.prefill_associations(possible_user_reviewers, { user_status: :organization })

        possible_team_reviewers = possible_reviewers.select { |reviewer| reviewer.is_a?(Team) }
        GitHub::PrefillAssociations.prefill_associations(possible_team_reviewers, [:organization])

        payload[:users] = possible_reviewers.map do |reviewer|
          reviewer_json_payload(pull, reviewer)
        end

        output = render json: payload

        timer.stop
        tags = ["type_ahead_enabled:#{type_ahead_enabled}", "empty_search_query:#{type_ahead_enabled && search_query.empty?}"]

        GitHub.dogstats.distribution("review_requests_controller.reviewers_menu_content.dist.time", timer.elapsed_ms, tags: tags)

        output
      end
    end
  end

  private

  def exclude_stale_user_review_requests?
    reviewer_user_ids.any? && params[:partial_last_updated].to_i > 0
  end

  def reviewer_json_payload(pull, reviewer)
    type = reviewer.is_a?(Team) ? "team" : "user"
    direct_request = pull.direct_review_request_for(reviewer)
    is_selected = !!direct_request
    is_disabled = is_selected && !pull.review_request_removable?(direct_request)
    name = if reviewer.is_a?(User)
      user_status = reviewer.user_status
      if !user_status&.expired? && user_status&.limited_availability?
        "#{reviewer.profile_name} (busy)"
      else
        reviewer.profile_name
      end
    else
      reviewer.name
    end

    login = if reviewer.is_a?(User)
      reviewer.display_login
    else
      reviewer.to_s
    end

    {
      id: reviewer.id,
      type: type,
      class: helpers.avatar_class_names(reviewer),
      selected: is_selected,
      disabled: is_disabled,
      avatar: reviewer.primary_avatar_url(40),
      login: login,
      name: name,
    }
  end

  # When a review is requested from a suggested user, we still want to show
  # the list of remaining suggestions. Stop showing suggestions when a review
  # request is made from a non-suggested user.
  #
  # Returns true the suggestion list should appear in the sidebar.
  def show_suggestions?(pull)
    suggestion_used? && pull.suggested_reviewers(actor: current_user).any?
  end

  def suggestion_used?
    params[:suggested_reviewer_id].present?
  end

  def re_requesting_review?
    params[:re_request_reviewer_id].present?
  end

  memoize def re_requesting_review_from
    User.where(id: params[:re_request_reviewer_id]).first
  end

  memoize def team_reviewers
    return [] unless current_repository.in_organization?
    return [] if re_requesting_review?

    ids = params.fetch(:reviewer_team_ids, []).select(&:present?).uniq
    current_repository.teams(immediate_only: false, include_all_repo_roles: current_repository.owner&.feature_enabled?(:reviewer_teams_all_repo_role)).closed.where(id: ids)
  end

  memoize def user_reviewers
    ids = Set.new
    ids |= reviewer_user_ids
    ids << params[:suggested_reviewer_id]
    ids.keep_if(&:present?)

    User.where(id: ids)
  end

  memoize def reviewer_user_ids
    params.fetch(:reviewer_user_ids, [])
  end

  # Build enough of a pull request object to render the requested reviewer
  # sidebar template on the pull request create page.
  #
  # Returns an unsaved PullRequest.
  def build_pull
    pull =
      if params[:range].present?
        comparison = GitHub::Comparison.from_range_or_ref(current_repository, params[:range], user: current_user)
        if comparison.valid? && comparison.viewable_by?(current_user)
          comparison.build_pull_request(user: current_user)
        end
      else
        current_repository.pull_requests.build(user: current_user)
      end

    return unless pull
    pull.issue = current_repository.issues.build

    if current_user_can_push?
      user_reviewers.pluck(:id).each do |id|
        pull.review_requests.build(reviewer_id: id, reviewer_type: "User")
      end

      team_reviewers.pluck(:id).each do |id|
        pull.review_requests.build(reviewer_id: id, reviewer_type: "Team")
      end
    end

    pull
  end

  def route_supports_advisory_workspaces?
    true
  end

  # confirmation is only required if a large number of users will be pinged
  def require_confirmation?(team)
    return false if team.review_request_delegation_enabled?

    team.large?(threshold: MAX_TEAM_SIZE_BEFORE_CONFIRMATION_REQUIRED)
  end
end
