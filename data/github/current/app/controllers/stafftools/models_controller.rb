# typed: true
# frozen_string_literal: true

class Stafftools::ModelsController < StafftoolsController
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Ballast,
  ApplicationRecord::Collab,
  ApplicationRecord::Configurations,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Copilot,
  only: [:index]

  CSP_EXCEPTIONS = {
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
  }.freeze
  before_action :add_csp_exceptions, only: [:index]

  def index
    @last_updated_at = AzureModels::CatalogItem.find_by(key: "all_models")&.updated_at
    @catalog_items = AzureModels::CatalogItem.where.not(key: "all_models").order(:key)
    render "stafftools/models/index", locals: { last_updated_at: @last_updated_at }
  end

  def update
    AzureModels::FetchCatalogItemsJob.perform_later
    flash[:notice] = "The job has been enqueued to update the catalog data."

    redirect_to :back
  end

  def update_visibility # rubocop:todo GitHub/UseRestfulActions
    @catalog_item = AzureModels::CatalogItem.find(params[:id])

    case params[:visibility]
    when "visible"
      @catalog_item.visible!
    when "staffshipped"
      @catalog_item.staffshipped!
    when "hidden"
      @catalog_item.hidden!
    end

    redirect_to :back
  end
end
