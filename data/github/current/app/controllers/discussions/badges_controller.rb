# typed: true
# frozen_string_literal: true

class Discussions::BadgesController < Discussions::BaseController
  before_action :login_required
  before_action :require_xhr
  after_action :flush_badge_timer_metrics

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:batch]

  def batch # rubocop:todo GitHub/UseRestfulActions
    item_batch = Discussion::CommentItemBatch.new(current_repository, params)
    keyed_responses = ActiveRecord::Base.connected_to(role: :reading) do
      records = item_batch.comments + item_batch.discussions
      GitHub::PrefillAssociations.prefill_associations(records, [:user])

      author_role_preloader = DiscussionTimeline::AuthorRolePreloader.new(
        rendered_records: records,
        repository: current_repository,
      )

      cpu_timer.track { author_role_preloader.preload }

      item_batch.map_inputs do |handler|
        handler.discussion do |discussion|
          render_author_badges(target: discussion, author_role_preloader: author_role_preloader)
        end

        handler.comment do |comment|
          render_author_badges(target: comment, author_role_preloader: author_role_preloader)
        end
      end
    end

    respond_to do |format|
      format.json do
        render json: keyed_responses
      end
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  def discussion_timeline_render_context_for(target)
    if target.is_a?(Discussion)
      DiscussionTimeline::DiscussionBodyRenderContext.new(
        target,
        viewer: current_user,
        cap_filter: cap_filter
      )
    else
      DiscussionTimeline::SingleCommentRenderContext.new(
        target.discussion,
        target,
        viewer: current_user,
        cap_filter: cap_filter
      )
    end
  end

  def render_author_badges(target:, author_role_preloader:)
    cpu_timer.track do
      render_context = discussion_timeline_render_context_for(target)
      timeline = DiscussionTimeline.new(render_context: render_context, author_role_preloader: author_role_preloader)

      render_to_string Discussions::AuthorBadgesComponent.new(
        discussion_or_comment: target,
        timeline: timeline,
      ), layout: false, formats: :html
    end
  end

  memoize def cpu_timer
    CpuTimer.new(
      "badge.request.total",
      tags: [
        "resource:discussions",
        "logged_in:#{current_user.present?}",
      ],
    )
  end

  def flush_badge_timer_metrics
    cpu_timer.flush
  end
end
