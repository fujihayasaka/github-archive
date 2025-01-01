# typed: true
# frozen_string_literal: true

require "github/pages/domain_health_checker"

class Stafftools::PagesController < StafftoolsController

  before_action :ensure_pages_enabled
  before_action :ensure_repo_exists
  before_action :ensure_https_enabled, only: [
    :https_status,
    :request_https_certificate,
    :delete_https_certificate,
  ]

  layout "layouts/stafftools/repository/storage"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "stafftools/pages/show", locals: {
      pending_protected_domains: never_verified_pending_protected_domains.pluck(:name).sort_by(&:length),
    }
  end

  def status # rubocop:todo GitHub/UseRestfulActions
    @health_check = GitHub::Pages::DomainHealthChecker.new(domain).check
    @alt_domain_health_check = GitHub::Pages::DomainHealthChecker.new(alt_domain).check if alt_domain.present?
    @alt_domain = alt_domain

    render "stafftools/pages/status", layout: false
  end

  def https_status # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Stafftools::RepositoryViews::PagesHTTPSStatusView,
      current_repository: current_repository,
      page: current_repository.page,
    )
    render "stafftools/pages/https_status", layout: false, locals: { view: view }
  end

  def unlock_build # rubocop:todo GitHub/UseRestfulActions
    current_repository.page.unlock_build
    flash[:notice] = "Unlocked current page build."
    redirect_to :back
  end

  def create
    pusher = current_repository.gh_pages_rebuilder(current_user)
    ref_name = current_repository.pages_branch

    # If deployment ID was given, build its ref name.
    page_deployment_id = params[:page_deployment_id].to_i
    if page_deployment_id > 0
      deployment = current_repository.page.deployments.where(id: page_deployment_id).first
      ref_name = deployment.ref_name if deployment
    end

    if pusher && current_repository.rebuild_pages(pusher, git_ref_name: ref_name)
      flash[:notice] = "Rebuilding the pages site for #{current_repository.name_with_owner} at ref '#{ref_name}'."
    else
      flash[:error] = "Couldn’t rebuild the pages site for #{current_repository.name_with_owner} at ref '#{ref_name}'."
    end
    redirect_to :back
  end

  def destroy
    page_deployment_id = params[:page_deployment_id].to_i

    if current_repository.page && page_deployment_id > 0
      deployment = current_repository.page.deployments.where(id: page_deployment_id).first
      if deployment
        if deployment.destroy
          flash[:notice] = "Deleted the deployment of #{current_repository.name_with_owner} with ref '#{deployment.ref_name}'."
        else
          flash[:notice] = "Failed to delete the deployment of #{current_repository.name_with_owner} with ref '#{deployment.ref_name}'."
        end
      else
        flash[:error] = "#{current_repository.name_with_owner} does not have a deployment with id '#{page_deployment_id}'."
      end
    else
      flash[:error] = "#{current_repository.name_with_owner} does not have Pages or a page deployment with the given ID."
    end

    redirect_to :back
  end

  def clear_generated_pages # rubocop:todo GitHub/UseRestfulActions
    page_deployment_id = params[:page_deployment_id].to_i

    if current_repository.page && page_deployment_id > 0
      # New hotness: a Page::Deployment!
      deployment = current_repository.page.deployments.where(id: page_deployment_id).first
      if deployment
        deployment.unpublish
        flash[:notice] = "Deleted the generated pages site for #{current_repository.name_with_owner} with ref '#{deployment.ref_name}'."
      else
        flash[:error] = "#{current_repository.name_with_owner} does not have a deployment with id '#{page_deployment_id}'."
      end
    elsif current_repository.page
      # Old & busted: pages replicas relating directly to page
      current_repository.page.unpublish
      flash[:notice] = "Deleted the generated pages site for #{current_repository.name_with_owner}."
    else
      flash[:error] = "#{current_repository.name_with_owner} does not have a generated pages site to delete."
    end

    redirect_to :back
  end

  def clear_domain # rubocop:todo GitHub/UseRestfulActions
    domain = current_repository.page.cname
    if domain
      unverified_domain_names = never_verified_pending_protected_domains.pluck(:name)
      # Page and Page::ProtectedDomain are both in the `repositories` database cluster
      Page.transaction do
        never_verified_pending_protected_domains.each { |domain| domain.unverified! }
        current_repository.page.clear_cname
      end
      # The custom domain of `current_repository` has been cleared in this request handler, but we must also clear any
      # other page cnames owned by this user, now that the domains are unverified.
      unverified_domain_names.each do |domain_name|
        Pages::DeleteProtectedDomainJob.perform_later(domain_name: domain_name, owner: current_repository.owner)
      end
      flash[:notice] = "Cleared the #{domain} domain from #{current_repository.name_with_owner}."
      if unverified_domain_names.present?
        flash[:warn] = "Unverified page owner's protected #{"domain".pluralize(unverified_domain_names.length)}: #{unverified_domain_names.join(", ")}."
      end
    else
      flash[:error] = "No custom domain for #{current_repository.name_with_owner}."
    end
    redirect_to :back
  end

  def request_https_certificate # rubocop:todo GitHub/UseRestfulActions
    current_page = current_repository.page

    domain = current_page.cname
    unless domain
      flash[:error] = "No custom domain for #{current_repository.name_with_owner}."
      redirect_to :back
      return
    end

    cert = current_page.certificate

    if cert.present?
      if cert.usable?
        flash[:notice] = "Certificate already exists for #{domain} and is usable."
      else
        cert.resume_flow
        flash[:notice] = "Certificate already exists for #{domain} in state '#{cert.current_state}'. Resuming the process."
      end
    else
      if current_page.eligible_for_certificate?
        if current_page.create_cname_certificate
          flash[:notice] = "Requesting a certificate for #{domain}. It can take up to an hour to propagate."
        else
          flash[:error] = "Something went wrong issuing a certificate for #{domain}. Please contact the Pages team."
        end
      else
        flash[:error] = "Domain #{domain} is not eligible for HTTPS at this time."
      end
    end

    redirect_to :back
  end

  def delete_https_certificate # rubocop:todo GitHub/UseRestfulActions
    current_page = current_repository.page

    domain = current_page.cname
    unless domain
      flash[:error] = "No custom domain for #{current_repository.name_with_owner}."
      redirect_to :back
      return
    end

    cert = current_page.certificate

    if cert.present?
      cert.destroy
      flash[:notice] = "Certificate for #{domain} destroyed."
    else
      flash[:error] = "No certificate present for #{domain}."
    end

    redirect_to :back
  end

  def restore_page # rubocop:todo GitHub/UseRestfulActions
    current_page = current_repository.page

    # if deleted_at is set, the page has been soft-deleted
    # this action will restore the page
    if current_page.present?
      if current_page&.deleted_at
        current_page.restore_deleted
        flash[:notice] = "Restored the page for #{current_repository.name_with_owner}."
      else
        flash[:error] = "The page for #{current_repository.name_with_owner} is not soft deleted."
      end
    else
      flash[:error] = "No page found for #{current_repository.name_with_owner}."
    end

    redirect_to :back
  end

  private

  def ensure_pages_enabled
    render_404 unless GitHub.pages_enabled?
  end

  def ensure_https_enabled
    render_404 unless GitHub.pages_custom_domain_https_enabled?
  end

  def domain
    if current_repository.page && current_repository.page.cname
      current_repository.page.cname
    elsif GitHub.enterprise?
      current_repository.pages_host_name
    else
      subdomain = "#{current_repository.owner.to_s.downcase}"
      "#{subdomain}.#{current_repository.pages_host_name}"
    end
  end

  def alt_domain
    # Check if the domain is an apex domain(ex. "example.com")
    return "www.#{domain}" if GitHubPages::HealthCheck::Domain.new(domain).apex_domain?

    # Check if domain starts with www since www subdomains will have an alternate domain. Custom subdomains will not have an alternative domain
    alt_domain = domain.delete_prefix("www.")
    return alt_domain if domain.downcase.start_with?("www.") && GitHubPages::HealthCheck::Domain.new(alt_domain).apex_domain?
    ""
  end

  memoize def never_verified_pending_protected_domains
    if current_repository.page.try(:cname)
      possible_names = [current_repository.page.cname, current_repository.page.parent_domain].compact
      Page::ProtectedDomain.where(name: possible_names)
        .where(owner: current_repository.owner, state: "pending", last_verified_at: nil)
        .limit(possible_names.length) # It's not possible to return more
    else
      Page::ProtectedDomain.none
    end
  end
end
