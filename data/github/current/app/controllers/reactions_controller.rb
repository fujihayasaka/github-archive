# typed: true
# frozen_string_literal: true

class ReactionsController < ApplicationController

  include Issues::RateLimitsDependency
  include Issues::RepositoryClusterDependency

  POSSIBLE_SUBJECT_TYPES = [
    Platform::Objects::CommitComment,
    Platform::Objects::Issue,
    Platform::Objects::IssueComment,
    Platform::Objects::Discussion,
    Platform::Objects::DiscussionComment,
    Platform::Objects::PullRequest,
    Platform::Objects::PullRequestReview,
    Platform::Objects::PullRequestReviewComment,
    Platform::Objects::Release,
    Platform::Objects::RepositoryAdvisory,
    Platform::Objects::RepositoryAdvisoryComment,
    Platform::Objects::TeamDiscussion,
    Platform::Objects::TeamDiscussionComment]

  FEED_CONTEXT = "feed"
  UNREACT_COMMAND = "unreact"

  around_action :with_replica_repository_cluster, only: [:update], if: :use_replica_cluster_for_reactions_show?
  before_action :validate_parameters, only: [:update]

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  def update
    content, command = params[:input][:content].to_s.split
    subject = active_record_object_from_subject_id

    return head :not_found unless subject

    emotion = subject.class.emotions.find { |e| e.platform_enum == content }

    return head :bad_request unless emotion
    return head :unauthorized unless subject.viewer_can_react?(current_user)

    subject = subject.issue if subject.is_a?(PullRequest)

    if command == UNREACT_COMMAND
      return head :not_found unless viewer_has_reacted?(subject, emotion)

      subject.unreact(actor: current_user, content: emotion.content)
    else
      subject.react(actor: current_user, content: emotion.content)
    end

    track_issue_edits_from_project_board(edited_fields: ["reactions"])

    if request.xhr?
      respond_to do |format|
        format.json do
          render json: {
            comment_header_reaction_button: comment_header_reaction_button(subject),
            reactions_container: reactions_container(subject, last_interacted_content: emotion.content),
          }
        end
      end
    else
      redirect_to :back
    end
  rescue Platform::Errors::NotFound
    head :not_found
  end

  private

  def perform_conditional_access_checks
    return with_replica_repository_cluster { super } if use_replica_cluster_for_reactions_show?
    super
  end

  def discussion_or_discussion_comment?(subject)
    subject.is_a?(Discussion) || subject.is_a?(DiscussionComment)
  end

  def reactions_container(subject, last_interacted_content: nil)
    if discussion_or_discussion_comment?(subject)
      locals = discussion_view_locals(subject)
      discussion_or_comment = locals[:discussion_or_comment]

      if params[:input][:context] == FEED_CONTEXT
        render_to_string(
          DashboardFeed::ReactionsComponent.new(
            target_global_id: discussion_or_comment.global_relay_id,
            reaction_path: discussion_or_comment.reaction_path,
            emotions: Discussion.emotions,
            reaction_count_by_content: discussion_or_comment.reactions.group(:content).pluck(:content, Arel.sql("count(*)")).to_h,
            viewer_reaction_contents: discussion_or_comment.reactions.where(user: current_user).distinct.pluck(:content),
            form_context: form_context,
          ),
          layout: false,
          formats: [:html],
        )
      else
        render_to_string(
          Discussions::ReactionsComponent.new(target: discussion_or_comment, last_interacted_content: last_interacted_content),
          layout: false,
          formats: [:html]
        )
      end
    elsif subject.is_a?(Release)
      if params[:input][:context] == FEED_CONTEXT
        render_to_string(
          partial: "dashboard_feeds/release_reactions",
          formats: [:html],
          locals: {
            release: subject,
          }
        )
      else
        render_to_string(
          Releases::ReactionsComponent.new(
            target: subject,
            include_summary: true,
            last_interacted_content: last_interacted_content,
          ),
          layout: false,
          formats: [:html],
        )
      end
    elsif subject.is_a?(CommitComment) && !subject.inline?
      render_to_string(
        Comments::ReactionsComponent.new(
          target: subject,
          context: params[:input][:context],
          ml: 3,
          mb: 3
        ),
        layout: false,
        formats: [:html],
      )
    else
      render_to_string(
        Comments::ReactionsComponent.new(
          target: subject,
          context: params[:input][:context]
        ),
        layout: false,
        formats: [:html],
      )
    end
  end

  def comment_header_reaction_button(subject)
    if discussion_or_discussion_comment?(subject)
      locals = discussion_view_locals(subject)
      render_to_string(Discussions::HeaderReactionButtonComponent.new(
        discussion_or_comment: locals[:discussion_or_comment],
        timeline: locals[:timeline],
      ), formats: [:html], layout: false)
    else
      render_to_string(
        partial: "comments/comment_header_reaction_button",
        formats: [:html],
        locals: { subject: subject, viewer_reaction_contents: viewer_reactions(subject) },
        layout: false,
      )
    end
  end

  def discussion_view_locals(subject)
    discussion = subject.is_a?(Discussion) ? subject : subject.discussion

    render_context = DiscussionTimeline::SingleCommentRenderContext.new(
      discussion,
      subject,
      viewer: current_user,
      cap_filter: cap_filter
    )
    timeline = DiscussionTimeline.new(render_context: render_context)
    { discussion_or_comment: subject, timeline: timeline }
  end

  def target_for_conditional_access
    # CAP bypass is fine here because it requires knowing the subject_id to react on.
    return :no_target_for_conditional_access unless subject_id # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    subject = active_record_object_from_subject_id
    if subject.try(:repository)
      subject.repository.owner
    elsif subject.try(:team)
      subject.team.organization
    else
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  rescue Platform::Errors::NotFound
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def subject_id
    params[:input][:subjectId]
  end

  memoize def active_record_object_from_subject_id
    typed_object_from_id(POSSIBLE_SUBJECT_TYPES, subject_id)
  end

  def viewer_has_reacted?(subject, emotion)
    viewer_reactions(subject).include?(emotion.content)
  end

  def viewer_reactions(subject)
    subject.reactions.where(user: current_user).distinct.pluck(:content)
  end

  def validate_parameters
    params.require(:input).tap do |input_params|
      input_params.permit(:subjectId, :context, :showTop, :hideOcticon, :content, content: Emotion.all.map(&:content).map(&:to_sym).push(:react))
      input_params.require(:subjectId)
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  def form_context
    return { showTop: params[:input][:showTop].to_i, hideOcticon: params[:input][:hideOcticon] } if params[:input][:showTop].present?
    {}
  end

  memoize def use_replica_cluster_for_reactions_show?
    with_replica_repository_cluster do
      begin
        subject = subject_id.present? ? active_record_object_from_subject_id : nil
        ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject&.class&.name)
      rescue Platform::Errors::NotFound
        false
      end
    end
  end
end
