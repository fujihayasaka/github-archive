# typed: true
# frozen_string_literal: true

class Discussions::ReactionsController < Discussions::BaseController
  before_action :require_xhr
  before_action :require_discussion

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:batch]

  def batch # rubocop:todo GitHub/UseRestfulActions
    item_batch = Discussion::CommentItemBatch.new(current_repository, params)
    GitHub::PrefillAssociations.prefill_batch_method(item_batch.models, :prelude_viewer_can_react, current_user)

    keyed_responses = ActiveRecord::Base.connected_to(role: :reading) do
      item_batch.map_inputs do |handler|
        handler.discussion do |discussion|
          render_to_string Discussions::ReactionsComponent.new(target: discussion), layout: false
        end

        handler.comment do |comment|
          if handler.button_only?
            render_header_reaction_button(comment)
          else
            render_to_string Discussions::ReactionsComponent.new(target: comment), layout: false
          end
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

  def render_header_reaction_button(comment)
    render_context = DiscussionTimeline::SingleCommentRenderContext.new(
      comment.discussion,
      comment,
      viewer: current_user,
      cap_filter: cap_filter,
    )

    render_to_string Discussions::HeaderReactionButtonComponent.new(
      discussion_or_comment: comment,
      timeline:  DiscussionTimeline.new(render_context: render_context),
    )
  end
end
