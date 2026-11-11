# typed: true
# frozen_string_literal: true

class Site::CustomerTermsController < Site::BaseController
  before_action :allow_iframe_embedding, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  stylesheet_bundle "legal"

  def index
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled?(:contentful_lp_customer_terms, current_user, default: false)

    page = Site::Contentful::Marketing::CustomerTerms::Pages::Terms.new.view_data

    if page.present?
      render "site/customer_terms/index", locals: { page: page }
    else
      render_404
    end
  end

  def show
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled?(:contentful_lp_customer_terms, current_user, default: false)

    document = Site::Contentful::Marketing::CustomerTerms::Pages::Term.new(id: params[:id]).view_data

    if document.present?
      render "site/customer_terms/show", locals: { document: document }
    else
      render_404
    end
  end

  def updates # rubocop:todo GitHub/UseRestfulActions
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled?(:contentful_lp_customer_terms, current_user, default: false)

    page = Site::Contentful::Marketing::CustomerTerms::Pages::Updates.new.view_data

    if page.present?
      render "site/customer_terms/updates", locals: { page: page }
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
