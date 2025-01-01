# typed: false
# frozen_string_literal: true

class CollectionsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  ITEMS_PER_PAGE = 20

  YOUTUBE_HOST = "www.youtube.com"

  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  before_action :dotcom_required
  before_action :add_csp_exceptions, only: [:show]
  before_action :ensure_not_multitenant_enterprise, only: [:index, :show]
  CSP_EXCEPTIONS = { frame_src: [YOUTUBE_HOST] }

  before_action :enable_fullstory, only: [:index, :show]
  before_action :add_fullstory_csp_exceptions, only: [:index, :show]

  # :site bundle dependency should be transitioned to only :explore
  stylesheet_bundle :site
  stylesheet_bundle :explore

  def index
    if request.xhr?
      render partial: "collections/featured_collections", locals: {
        featured_collections: ExploreCollection.featured_and_shuffled,
        collections: ExploreCollection.paginate(page: params.fetch(:page, 1)),
      }
    else
      context_region_preset :explore
      render "collections/index", locals: {
        featured_collections: ExploreCollection.featured_and_shuffled,
        collections: ExploreCollection.paginate(page: params.fetch(:page, 1)),
      }
    end
  end

  def show
    collection = ExploreCollection.find_by(slug: params[:slug])
    return render_404 unless collection

    items = collection.items.includes(:content).visible.paginate(page: current_page, per_page: ITEMS_PER_PAGE)
    if logged_in?
      repos = items.filter_map { |i| i.content if i.repository? }
      GitHub::PrefillAssociations.prefill_batch_method(repos, :starred_by?, current_user)
    end

    if request.xhr?
      respond_to do |format|
        format.html do
          render partial: "collections/collection_items", locals: { collection: collection, items: items }
        end
      end
    else
      context_region_preset :explore
      render "collections/show", locals: { collection: collection, items: items }
    end
  end

  private

  def ensure_not_multitenant_enterprise
    render_404 if GitHub.multi_tenant_enterprise?
  end
end
