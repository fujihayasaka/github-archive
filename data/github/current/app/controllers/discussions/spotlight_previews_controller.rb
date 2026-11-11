# typed: true
# frozen_string_literal: true

class Discussions::SpotlightPreviewsController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    spotlight = DiscussionSpotlight.new(spotlight_params)
    spotlight.repository = current_repository
    spotlight.discussion = discussion

    render Discussions::SpotlightComponent.new(spotlight: spotlight, preview: true, org_param: org_param), layout: false
  end

  private

  def spotlight_params
    params.require(:discussion_spotlight).
      permit(:emoji, :preconfigured_color, :pattern)
  end
end
