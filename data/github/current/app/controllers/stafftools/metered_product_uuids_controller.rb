# typed: true
# frozen_string_literal: true

class Stafftools::MeteredProductUuidsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    @product_uuids = get_metered_product_uuids
    render "stafftools/metered_product_uuids/index", locals: { product_uuids: @product_uuids }
  end

  def show
    @product_uuid = Billing::ProductUUID.find(params[:id])
    render "stafftools/metered_product_uuids/show", locals: { product_uuid: @product_uuid }
  end

  private

  def get_metered_product_uuids
    Billing::ProductUUID.where(metered: true).sort_by { |product_uuid| [product_uuid.product_type, product_uuid.product_key] }
  end
end
