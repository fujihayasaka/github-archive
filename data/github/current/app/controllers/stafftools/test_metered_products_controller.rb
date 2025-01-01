# typed: true
# frozen_string_literal: true

class Stafftools::TestMeteredProductsController < StafftoolsController
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
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/test_metered_products/index", locals: { **default_params }
  end

  def create
    case permitted_params[:tester_action]
    when "calculate_usage"
      usage_breakdown = metered_product_tester.calculate_test_usage
      unless usage_breakdown
        flash[:error] = "Error calculating test usage: #{metered_product_tester.error_message}"
      end

      render "stafftools/test_metered_products/index", locals: { **form_params.merge(
        usage_breakdown: usage_breakdown.to_h.with_indifferent_access,
      ) }
    when "emit_test_usage"
      metered_product_tester.emit_test_usage
      unless usage_emitted = metered_product_tester.usage_emitted?
        flash[:error] = "Please fill in all fields"
      end

      render "stafftools/test_metered_products/index", locals: { **form_params.merge(usage_emitted: usage_emitted) }
    else
      redirect_to stafftools_test_metered_products_path
    end
  end

  private

  memoize def metered_product_tester
    Billing::MeteredProductTester.new(
      product_name: permitted_params[:product_name],
      product_sku_name: permitted_params[:product_sku_name],
      quantity: permitted_params[:quantity],
      source: permitted_params[:source],
      user: current_user,
    )
  end

  def form_params
    default_params.merge(
      permitted_params.slice(:product_name, :product_sku_name, :quantity, :source).to_h.symbolize_keys
    )
  end

  def permitted_params
    params.permit(%i[product_name product_sku_name quantity source tester_action commit authenticity_token])
  end

  def default_params
    {
      user: current_user,
      usage_breakdown: nil,
      usage_emitted: false,
      product_name: nil,
      product_sku_name: nil,
      quantity: nil,
      source: nil,
    }
  end
end
