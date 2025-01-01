# typed: true
# frozen_string_literal: true

class Site::Readme::DeveloperStoriesController < Site::Readme::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:show],
    optional: true

  def index
    category = Site::Contentful::Readme::DeveloperStory.category

    if category.present?
      render "site/readme/categories/show", locals: {
        category: category,
        story_class: Site::Contentful::Readme::DeveloperStory
      }
    else
      render_404
    end
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::DeveloperStories::ShowPage, story_slug: params[:id], for_readme_staff: readme_staff?)

    page_data = Site::Contentful::Readme::Pages::DeveloperStories::ShowPage.new(story_slug: params[:id], for_readme_staff: readme_staff?).view_data

    render_404 and return if page_data[:story].blank?

    developer_story_user = if page_data[:story][:github_user].present?
      User.find_by(login: page_data[:story][:github_user][:handle])
    else
      nil
    end

    # Ensure story klass is available for fetching the body
    page_data[:story][:klass] ||= "Site::Contentful::Readme::DeveloperStory"

    extra_page_data = {
      developer_story_user: developer_story_user,
      developer_story_user_public_email: developer_story_user&.publicly_visible_email(logged_in: logged_in?),
      developer_story_user_public_organizations_sample: developer_story_user&.public_organizations&.sample(8) || [],
      developer_story_user_public_sponsorships_sample: developer_story_user&.sponsorships_as_sponsor&.privacy_public&.sample(8) || [],
      developer_story_user_has_approved_sponsors_account: developer_story_user&.approved_sponsors_listing.present?,
    }

    render "site/readme/developer_stories/show", locals: { page_data: page_data.merge(extra_page_data) }
  end
end
