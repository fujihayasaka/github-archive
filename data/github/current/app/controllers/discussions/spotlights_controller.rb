# typed: true
# frozen_string_literal: true

class Discussions::SpotlightsController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_spotlight_management
  before_action :require_spotlight, only: [:update, :destroy, :edit]
  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:new]

  def new
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    spotlight = DiscussionSpotlight.new(
      preconfigured_color: random_color,
      pattern: DiscussionSpotlight.pattern_names.sample,
      discussion: discussion,
      repository: discussion.repository
    )

    render Discussions::Spotlights::FormComponent.new(spotlight: spotlight, org_param: org_param), layout: false
  end

  def create
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    spotlight = DiscussionSpotlight.new(spotlight_params)
    spotlight.spotlighted_by = current_user
    spotlight.discussion = discussion

    if spotlight.save
      flash[:notice] = "Discussion has successfully been pinned."
    else
      flash[:error] = "Could not pin this discussion at this time: " \
        "#{spotlight.errors.full_messages.to_sentence}"
    end
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  def edit
    render Discussions::Spotlights::FormComponent.new(spotlight: spotlight, org_param: org_param), layout: false
  end

  def update
    if spotlight.update(spotlight_params)
      flash[:notice] = "Discussion pin has been updated."
    else
      flash[:error] = "Could not update this pinned discussion at this time: " \
        "#{spotlight.errors.full_messages.to_sentence}"
    end
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  def destroy
    spotlight.actor = current_user
    if spotlight.destroy
      flash[:notice] = "Discussion has been unpinned."
    else
      flash[:error] = "Could not unpin this discussion at this time: " \
        "#{spotlight.errors.full_messages.to_sentence}"
    end
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  private

  memoize def spotlight
    DiscussionSpotlight.for_repository(current_repository).
      for_discussion(discussion).find(params[:id])
  end

  def random_color
    DiscussionSpotlight.preconfigured_color_names.sample
  end

  def require_spotlight
    render_404 unless spotlight
  end

  def spotlight_params
    params.require(:discussion_spotlight).
      permit(:position, :preconfigured_color, :custom_color, :pattern)
  end

  def require_spotlight_management
    render_404 unless current_user.can_manage_discussion_spotlights?(current_repository)
  end
end
