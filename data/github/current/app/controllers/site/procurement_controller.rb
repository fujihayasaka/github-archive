# typed: true
# frozen_string_literal: true

class Site::ProcurementController < Site::BaseController
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :allow_iframe_embedding, only: :show

  depends_on_clusters ApplicationRecord::Mysql1

  VALID_PDF_PATH = Dir.glob("#{Rails.root}/public/static/documents/procurement/*.pdf").freeze

  stylesheet_bundle "legal"

  def index
    page = Site::Contentful::Marketing::Page.find("procurement-legal")

    if page.present?
      render "site/procurement/index", locals: { page: page }
    else
      render_404
    end
  end

  def show
    document = Site::Contentful::Marketing::Document.find("/procurement-legal/#{params[:id]}")

    if document.present?
      render "site/procurement/show", locals: { document: document }
    else
      render_404
    end
  end

  private

  def allow_iframe_embedding
    respond_to do |format|
      format.pdf do
        csp_exceptions = {
          object_src: [SecureHeaders::PolicyManagement::SELF],
          frame_ancestors: [SecureHeaders::PolicyManagement::SELF]
        }

        SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
        SecureHeaders.override_x_frame_options(request, SecureHeaders::XFrameOptions::SAMEORIGIN)
      end

      format.html do
        csp_exceptions = {
          frame_src: [SecureHeaders::PolicyManagement::SELF, GitHub.contentful_marketing_asset_host_url],
          object_src: [SecureHeaders::PolicyManagement::SELF, GitHub.contentful_marketing_asset_host_url]
        }

        SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
      end
    end
  end
end
