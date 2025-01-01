# typed: true
# frozen_string_literal: true

class Site::Enterprise::ContactRequests::ThanksController < Site::Enterprise::BaseController
  around_action :switch_locale

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  stylesheet_bundle "enterprise-contact"

  def index
    customer_stories = %w(postmates spotify 3m).map do |parameterized_name|
      ExploreFeed::CustomerStory.find_by_parameterized_name(parameterized_name)
    end.compact

    return Site::LandingPagesController.dispatch(:show, request, response) if feature_enabled_globally_or_for_current_user?(:contentful_lp_contact_sales_form)

    render "site/enterprise/contact_requests/thanks", locals: {
      enterprise_email: "enterprise@github.com",
      sales_phone_number: "+1-877-958-8742",
      formatted_sales_phone_number: "+1 (877) 958-8742",
      enterprise_docs_url: "#{GitHub.enterprise_support_link}",
      customer_stories: customer_stories,
      microsoft_analytics_order_id: microsoft_analytics_order_id,
      microsoft_analytics_product_title: params["utm_content"]
    }
  end

  private

  def microsoft_analytics_order_id
    return unless params[:ref_id].present?
    return unless params["utm_content"].present?

    timestamp = Time.now.strftime("%m%d") # month, day
    Digest::SHA256.hexdigest("#{timestamp}-#{params["utm_content"]}-#{params[:ref_id]}")
  end
end
