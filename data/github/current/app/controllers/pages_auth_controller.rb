# typed: true
# frozen_string_literal: true

class PagesAuthController < ApplicationController

  before_action :login_required
  # Permissions
  before_action :access_check
  javascript_bundle :settings
  include PagesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:authenticate]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:authenticate],
    optional: true

  def authenticate # rubocop:todo GitHub/UseRestfulActions
    log_data.update({
      "gh.page.id" => params[:page_id],
      "gh.page.subdomain" => params[:page_subdomain],
      "gh.repo.id" => current_repository&.id,
      "gh.user.id" => current_user&.id,
    })

    return render_404 unless params[:path].present?
    return render_404 unless params[:nonce].present?
    return render_404 unless @page.private?
    return render_404 unless current_repository.can_have_private_pages?

    uuid_regex = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    return render_404 unless uuid_regex.match?(params[:nonce].to_s.downcase)

    token = @page.auth_token(session: user_session)
    query_params = {
      path:     params[:path],
      page_id:  @page.id,
      nonce:    params[:nonce],
      token:    token
    }

    # Technically page_id is the only query param that pages-router needs to handle the `.github/auth` endpoint,
    # but including the page_subdomain param (in private mode, if present) will allow it to look up the current
    # auth state in cache, rather than making another internal pages auth API request.
    if params[:page_subdomain].present? && GitHub.flipper[:pages_auth_controller_accepts_subdomain].enabled?
      query_params = query_params.merge({
        page_subdomain: params[:page_subdomain]
      })
    end

    # Include the deployment token if present (when :pages_preview_deployments is removed, do that inconditionally)
    if params[:deployment_token].present? && (GitHub.flipper[:pages_preview_deployments].enabled?(current_repository) || GitHub.flipper[:pages_preview_deployments].enabled?(current_repository.owner))
      query_params = query_params.merge({
        deployment_token: params[:deployment_token]
      })
    end

    redirect_url = "#{GitHub.pages_auth_url}/redirect?#{query_params.to_param}"

    render "pages_auth/meta_refresh_redirect_private_page", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"

    rescue Addressable::URI::InvalidURIError
      render_404
  end

  private

  def current_repository
    return @current_repository if defined?(@current_repository)

    # To support private mode, pages-router may use the page subdomain instead of the page id
    # in order to make the auth request before verifying that the page even exists.

    @page = if params[:page_id]
      Page.find_by(id: params[:page_id])
    elsif params[:page_subdomain] && GitHub.flipper[:pages_auth_controller_accepts_subdomain].enabled?
      subdomain = if GitHub.multi_tenant_enterprise?
        "#{params[:page_subdomain]}_#{GitHub::CurrentTenant.get.shortcode}"
      else
        params[:page_subdomain]
      end
      Page.where(subdomain: subdomain).or(Page.where(custom_subdomain: subdomain)).first
    end

    return render_404 if @page.nil?

    @current_repository = @page.repository
  end

  def target_for_conditional_access
    current_repository.owner
  end

  def access_check
    # if the page is public and go thru the auth flow, return not found
    return render_404 if @page.public
    unless @page.private? && current_repository.pullable_by?(current_user)
      # Make sure we don't leak any data from a repository object the user cannot see:
      clear_current_repository

      render "pages_auth/forbidden",
        layout: "site",
        status: :forbidden,
        formats: [:html]
    end
  end
end
