# typed: true
# frozen_string_literal: true

class Discussions::PagesController < Discussions::BaseController
  before_action :require_discussion

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  def show
    render Discussions::CollapsibleTimelineComponent.new(timeline: discussion_timeline, org_param: org_param), layout: false
  end
end
