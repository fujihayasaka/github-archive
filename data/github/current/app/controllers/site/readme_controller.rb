# typed: true
# frozen_string_literal: true

class Site::ReadmeController < Site::Readme::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :show, :rss]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index, :rss],
    optional: true

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::IndexPage, for_readme_staff: readme_staff?)

    page_data = Site::Contentful::Readme::Pages::IndexPage.new(for_readme_staff: readme_staff?).view_data

    render "site/readme/home/index", locals: { page_data: page_data }
  end

  def rss # rubocop:todo GitHub/UseRestfulActions
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::RssPage)

    page_data = Site::Contentful::Readme::Pages::RssPage.new.view_data

    render "site/readme/home/rss_feed", locals: { page_data: page_data }
  end

  def show
    readme_story = Site::Readme::LegacyStoryData::DATA.find do |story_data|
      story_data[:slug] == params[:id] || story_data[:old_slug] == params[:id]
    end

    if readme_story.present?
      redirect_from_legacy_url(readme_story)
    else
      render_404
    end
  end

  private

  def redirect_from_legacy_url(story)
    path = case story[:category]
    when "guides"
      readme_guide_url(story[:slug])
    when "featured"
      readme_featured_article_url(story[:slug])
    when "stories"
      readme_developer_story_url(story[:slug])
    when "podcast"
      readme_podcast_url(story[:slug])
    end

    redirect_to(path, status: 301)
  end
end
