# typed: true
# frozen_string_literal: true

class Biztools::Marketplace::StoriesController < BiztoolsController # rubocop:todo GitHub/ControllersShouldHaveTests

  before_action :marketplace_required

  def index
    stories = Marketplace::Story.all
    story_count = stories.count
    stories = stories.unscope(:order).order(published_at: :desc).limit(100)

    render "biztools/marketplace/stories/index", locals: { stories: stories, story_count: story_count }
  end
end
