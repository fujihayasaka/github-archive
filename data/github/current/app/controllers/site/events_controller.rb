# typed: true
# frozen_string_literal: true

class Site::EventsController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index, :show],
    optional: true

  CSP_EXCEPTIONS = {
    img_src: [ExploreFeed::Event::FEED_URL, GitHub.contentful_marketing_image_host_url],
  }

  layout "application"

  stylesheet_bundle "explore"

  def index
    if feature_enabled_globally_or_for_current_user?(:contentful_events_feed)
      RevalidatePageJob.perform_later(Site::Contentful::Marketing::Events::Pages::IndexPage)
      events_page_data = Site::Contentful::Marketing::Events::Pages::IndexPage.new.view_data

      render "site/contentful/events/index", locals: {
        page: events_page_data[:page_data],
        events: events_page_data[:events],
        sponsored_events: events_page_data[:sponsored_events]
      }
    else
      render "site/events/index"
    end
  end

  def show
    if feature_enabled_globally_or_for_current_user?(:contentful_events_feed)
      RevalidatePageJob.perform_later(Site::Contentful::Marketing::Events::Pages::ShowPage, slug: params[:id])
      page_data = Site::Contentful::Marketing::Events::Pages::ShowPage.new(slug: params[:id]).view_data

      if page_data[:event].present?
        render "site/contentful/events/show", locals: { event: page_data[:event] }
      else
        render_404
      end
    else
      if event.present?
        render "site/events/show", locals: { event: event }
      else
        render_404
      end
    end
  end

  private

  def event # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_event ||= ExploreFeed::Event.fetch_by_parameterized_name(params[:id])
  end
end
