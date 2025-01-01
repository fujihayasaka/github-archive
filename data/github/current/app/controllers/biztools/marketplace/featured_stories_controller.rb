# typed: true
# frozen_string_literal: true

class Biztools::Marketplace::FeaturedStoriesController < BiztoolsController

  before_action :marketplace_required

  def create
    story = Marketplace::Story.find(params[:id])
    if story.update(featured: true)
      flash[:notice] = "Successfully marked the story as featured."
    else
      flash[:error] = story.errors.full_messages.to_sentence
    end

    redirect_to biztools_marketplace_stories_path
  end

  def destroy
    story = Marketplace::Story.find(params[:id])
    if story.update(featured: false)
      flash[:notice] = "Successfully unfeatured the story."
    else
      flash[:error] = story.errors.full_messages.to_sentence
    end

    redirect_to biztools_marketplace_stories_path
  end
end
