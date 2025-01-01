# typed: true
# frozen_string_literal: true

class Discussions::SpotlightPositionsController < Discussions::BaseController
  before_action :login_required
  before_action :require_ability_to_manage_spotlights
  layout false

  def update
    DiscussionSpotlightPositioner.reposition!(current_repository, ordered_spotlight_ids)
    head 200
  end

  private

  memoize def ordered_spotlight_ids
    GitHub::JSON.parse(request.raw_post)["spotlight_ids"]
  end

  def require_ability_to_manage_spotlights
    render_404 unless current_user.can_manage_discussion_spotlights?(current_repository)
  end
end
