# typed: false
# frozen_string_literal: true

require "github/pages/domain_health_checker"

class PagesController < AbstractRepositoryController
  include PagesHelper

  # Permissions
  before_action :ensure_repo_writable, except: [:status, :https_status]
  before_action :ensure_repo_admin_access, except: [:source, :build_type, :delete_deployment]
  before_action :manage_settings_pages_permissions_required, only: [:source, :build_type, :delete_deployment]
  before_action :ensure_org_allows_pages_creation, only: :source
  before_action :ensure_page_not_disabled, except: [:visibility, :source]
  before_action :ensure_pages_creation_allowed, only: :source

  # Feature availability
  before_action :ensure_repo_has_page, except: [:build_type, :source]
  before_action :ensure_https_redirect_available, only: :https_redirect
  before_action :ensure_https_redirect_enabled, only: :https_status
  before_action :ensure_cname_available, only: :cname

  # status fragment should not be redirected e.g. for staff billing lock
  # note: status is still subject to admin_only restriction
  skip_before_action :ask_the_gatekeeper, only: [:status, :https_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Pages,
    only: [:certificate_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Pages,
    only: [:domain_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Pages,
    only: [:status]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:certificate_status, :status],
    optional: true

  javascript_bundle :settings
  include PagesHelper

  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:build_type]

  # set build type
  # a transitional controller endpoint while bring-your-own-workflow is in beta, and users can switch between build types
  def build_type # rubocop:todo GitHub/UseRestfulActions
    render_404 and return unless pages_build_types_enabled?

    if !Page.build_types.key?(params[:build_type])
      flash[:error] = "Invalid build type: #{params[:build_type]}"
    else
      page = current_repository.page
      old_build_type = page&.build_type
      page = current_repository.build_page(build_type: params[:build_type], source_ref_name: current_repository.default_branch, source_subdir: "/") if page.nil?
      old_cname = page.cname

      if old_build_type != params[:build_type]
        if old_build_type == "workflow" && page.source_ref_name.nil?
          page.update(build_type: params[:build_type], source_ref_name: current_repository.default_branch, source_subdir: "/")
        else
          page.update(build_type: params[:build_type])
        end
        flash[:notice] = "GitHub Pages source saved."
      end
    end

    # After updating page from workflow, if it had a cname, we need to ensure it exists in the repository
    if old_cname.present? && old_build_type == "workflow"
      page.write_cname(old_cname, current_user)
    end

    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to redirect_path }
    end
  end

  # delete pages_deployment
  def delete_deployment # rubocop:todo GitHub/UseRestfulActions
    page = current_repository.page

    return render_404 unless page

    # for legacy type the deployment id can be enmpty and using page_id + built_revision here to lookup replica, thus clear it as well.
    page.update(built_revision: nil)

    # clear deployments so the remained content can be garbage collected by cronjob.
    page.deployments&.delete_all

    flash[:notice] = "GitHub Pages unpublished."
    redirect_to redirect_path(show_tip: params[:show_tip])
  end

  # set page source
  # allowed on project repo, even when no page exists yet
  # triggers page rebuild if source changed
  def source # rubocop:todo GitHub/UseRestfulActions
    new_source = params[:source]
    new_source_dir = params[:source_dir]
    is_user_pages_repo = current_repository.is_user_pages_repo?
    if !Page::VALID_SUBDIRS.include?(new_source_dir)
      flash[:error] = "Invalid GitHub Pages source folder."
    # Disable delete Pages if current repository is user repo or current repository is a project repository and contains gh-pages branch.
    elsif new_source.nil? && (is_user_pages_repo || (!is_user_pages_repo && current_repository.has_gh_pages_branch?))
      flash[:error] = "Pages cannot be disabled for this repository."
    elsif !current_repository.can_have_private_pages? && current_repository.is_enterprise_managed?
      flash[:error] = "Enterprise Managed Repositories can't have public GitHub Pages."
    else
      page = current_repository.page
      no_page = page.nil?
      old_source = page&.source_ref_name
      old_source_subdir = page&.source_subdir

      # Prevent this operation if the page is soft-deleted. The only allowed change to `source` is to set it to "", which removes the page.
      if operation_prevented_by_soft_deletion?
        if new_source.present?
          flash[:error] = "Disabled Pages may not be modified, except to make them visible or destroy them."
        else
          current_repository.page&.destroy
        end
        return redirect_to redirect_path(show_tip: params[:show_tip])
      end

      if new_source.nil?
        page&.clear_source
      elsif page.nil?
        page = current_repository.build_page(source_ref_name: new_source, source_subdir: new_source_dir, build_type: "legacy")
        page.set_subdomain_to_match_visibility
        page.save
      else
        page.set_subdomain_to_match_visibility
        page.set_source(ref_name: new_source, subdir: new_source_dir, build_type: "legacy")
      end

      if no_page || page.source_ref_name != old_source || page.source_subdir != old_source_subdir
        current_repository.rebuild_pages current_user
        flash[:notice] = "GitHub Pages source saved."
      end
    end
    redirect_to redirect_path(show_tip: params[:show_tip])
  end

  # render fragment to show pages page status with build or cname error message
  def status # rubocop:todo GitHub/UseRestfulActions
    if current_repository.plan_supports_pages? || (current_user.enabled? && current_repository.unsupported_pages?)
      view = create_view_model(
        EditRepositories::AdminScreen::PagesStatusView,
        repository: current_repository,
        cname_error: cname_error,
        user: current_user,
      )
      render "edit_repositories/admin_screen/pages_status", layout: false, locals: { view: view }
    else
      render_404
    end
  end

  def certificate_status # rubocop:todo GitHub/UseRestfulActions
    cert_status = get_certificate_status(current_repository)
    return render_404 unless cert_status
    return render_404 if cert_status == :approved && params[:display_approval_state].blank?

    view = create_view_model(
      EditRepositories::AdminScreen::PagesCertificateStatusView,
      state: cert_status,
      cname: current_repository.page.cname
    )
    render "edit_repositories/admin_screen/pages_certificate_status", layout: false, locals: { view: view }
  end

  # render fragment to show pages custom domain https status
  def https_status # rubocop:todo GitHub/UseRestfulActions
    bump_certificate

    view = create_view_model(
      EditRepositories::AdminScreen::PagesHTTPSView,
      current_repository: current_repository,
      current_user: current_user,
    )
    render "edit_repositories/admin_screen/pages_https", layout: false, locals: { view: view }
  end

  def request_https_certificate # rubocop:todo GitHub/UseRestfulActions
    current_page = current_repository.page

    domain = current_page.cname
    unless domain
      flash[:error] = "No custom domain for #{current_repository.name_with_display_owner}."
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

  # Return status of domain and alt_domain
  # This is used in the new view components
  # The components have their own logic for displaying
  # these messages
  def domain_status # rubocop:todo GitHub/UseRestfulActions
    # perform DNS check only if everything else looks peachy
    return render_404 unless GitHub.pages_custom_cnames?
    return render_404 unless current_repository.page.cname?
    page = current_repository.page
    cname = page.cname

    checks = []

    operation_result = Pages::KV.store.get(page.dns_kv_key).value!
    if operation_result.present?
      checks = JSON.parse(operation_result, { symbolize_names: true })
    else
      # if no operation result, check for status of job
      job_status = Pages::KV.store.get(page.job_status_kv_key).value!
      if job_status.blank?
        ActiveRecord::Base.connected_to(role: :writing) do
          Pages::KV.store.set(page.job_status_kv_key, "queued", expires: 2.minutes.from_now)
        end
        PagesDnsHealthCheckJob.perform_later(page.id)
      end
    end

    # If we don't have any checks yet, tell the user to wait
    if checks.blank?
      return render Pages::CustomDomainComponent.new(
        state: :queued,
        repository: current_repository,
      ), layout: false
    end

    # If we have checks, we can tell the user the status of the domain
    alt_domain = get_alt_domain(cname)
    # if no alt_domain, set state based on status of primary
    if alt_domain.blank?
      state = checks[:domain][:valid?] ? :valid : :invalid
    else
      state = case [checks[:domain][:valid?], checks[:alt_domain][:valid?]]
      when [true, true]
        :both_valid
      when [true, false]
        :primary_only
      when [false, true]
        :alternate_only
      when [false, false]
        :both_invalid
      end
    end

    warning = checks.dig(:domain, :warning) || checks.dig(:alt_domain, :warning)

    certificate = current_repository.page&.certificate

    # If DNS is valid for both, but the certificate doesn't cover the alt_domain,
    # kick off a job to update the certificate.
    dns_changed = (state == :both_valid && certificate&.alt_domain.nil?)
    bump_certificate(dns_changed: dns_changed)

    render Pages::CustomDomainComponent.new(
      state: state,
      warning: warning,
      repository: current_repository,
      primary_check: checks[:domain],
      alt_check: checks[:alt_domain]
    ), layout: false
  end

  def cname # rubocop:todo GitHub/UseRestfulActions
    param_cname = params[:cname]
    if params[:commit] == "Remove"
      param_cname = ""
    end

    if (cname = current_repository.page.write_cname(param_cname, current_user))
      if cname.blank?
        flash[:notice] = "Custom domain removed. Please remember to remove any GitHub Pages DNS records for this domain if you do not plan to continue using it with GitHub Pages."
      else
        flash[:notice] = "Custom domain \"#{cname}\" saved."
      end
      GitHub.dogstats.increment "pages", tags: ["action:cname"]
    else
      flash[:notice] = "No changes to custom domain."
    end
  rescue Page::InvalidCNAME => e
    flash[:error] = e.message
  rescue Git::Ref::ProtectedBranchUpdateError
    flash[:error] = "Unable to commit CNAME to protected branch."
  rescue Git::Ref::RepositoryRuleViolationError => e
    flash[:error] = e.detailed_message
  ensure
    redirect_to redirect_path
  end

  def custom_subdomain # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.multi_tenant_enterprise?

    current_page = current_repository.page

    if params[:commit] == "Remove"
      if current_page.custom_subdomain?
        old_display_subdomain = current_page.display_custom_subdomain
        current_page.update(custom_subdomain: nil)
        flash[:notice] = "Custom subdomain #{old_display_subdomain} removed."
      else
        flash[:error] = "No custom subdomain to remove."
      end
      return redirect_to redirect_path
    end

    new_custom_subdomain = params[:custom_subdomain].to_s.downcase

    if new_custom_subdomain.blank? || (new_custom_subdomain == current_page.display_custom_subdomain)
      flash[:error] = "Custom subdomain was not changed."
      return redirect_to redirect_path
    end

    if new_custom_subdomain == current_page.display_subdomain
      flash[:error] = "Custom subdomain was not changed. To user your default subdomain, remove the custom subdomain."
      return redirect_to redirect_path
    end

    begin
      success = current_page.set_custom_subdomain(new_custom_subdomain)
      if success
        flash[:notice] = "Custom subdomain #{new_custom_subdomain} saved."
      else
        flash[:error] = "Couldn't set custom subdomain to #{new_custom_subdomain}."
      end
    rescue Page::InvalidCustomSubdomain => e
      flash[:error] = e.message
    ensure
      redirect_to redirect_path
    end
  end

  def https_redirect # rubocop:todo GitHub/UseRestfulActions
    enable = params[:pages_https_redirect] == "1"
    if current_repository.page.update(https_redirect: enable)
      if request.xhr?
        head :ok
      else
        flash[:notice] = "HTTPS redirects #{(enable ? "enabled" : "disabled")}"
        redirect_to :back
      end
    else
      flash[:error] = current_repository.page.errors.full_messages.to_sentence
    end
  end

  def visibility # rubocop:todo GitHub/UseRestfulActions
    return render_404 if GitHub.multi_tenant_enterprise? # No visibility changes in multi-tenant
    return render_404 unless GitHub.private_pages_enabled?
    # In the forked repository we want to check the plan supported in the destination
    # repository and not honour the source repository
    if current_repository.fork?
      return render_404 unless current_repository.owner&.plan_supports?(:private_pages)
    else
      # Dont' render 404 if the page is soft-deleted, in order to allow the owner to change visibility to public
      # and restore the page.
      return render_404 unless current_repository.plan_supports?(:private_pages) || operation_prevented_by_soft_deletion?
    end

    if operation_prevented_by_soft_deletion? && params[:public] == "false"
      flash[:error] = "Disabled Pages may not be modified, except to make them visible or destroy them."
      return redirect_to redirect_path
    end

    # User/org pages aren't currently allowed to have Private pages
    return render_404 if current_repository.is_user_pages_repo?
    # Public repos cannot change their visibility
    return render_404 unless current_repository.private?
    # Respect org policy when switching visibility
    return render_404 unless current_repository.org_members_can_create_pages?(visibility: params[:public] == "true" ? :public : :private)
    # EMUs can't have public content
    return render_404 if params[:public] == "true" && !current_repository.can_have_public_pages?

    if current_repository.page.update(public: params[:public])
      # This will serve to flush the cache from Fastly for this page, we want to force Fastly to fetch from origin when changing
      # a page visibility from Public to Private or vice-versa
      current_repository.rebuild_pages current_user
      # Publish visibility change event to Hydro
      GlobalInstrumenter.instrument "pages.visibility_change", {
        actor: current_user,
        page: current_repository.page,
        public: current_repository.page.public
      }
      if request.xhr?
        head :ok
      else
        flash[:notice] = "GitHub Page visibility is #{params[:public] == "true" ? "public" : "private"}"
        redirect_to :back
      end
    else
      flash[:error] = current_repository.page.errors.full_messages.to_sentence
      redirect_to redirect_path
    end
  end

  private

  def redirect_path(url_params = {})
    path = "/#{current_repository.name_with_display_owner}/settings/pages"
    url_params = url_params.compact_blank
    path += "?#{url_params.to_query}" if url_params.present?
    path
  end

  def ensure_repo_writable
    render_404 unless current_repository.writable?
  end

  def ensure_repo_write_access
    render_404 unless current_repository.writable_by?(current_user)
  end

  def ensure_repo_admin_access
    render_404 unless current_repository.adminable_by?(current_user)
  end

  def manage_settings_pages_permissions_required
    render_404 unless current_repository.async_can_toggle_page_settings?(current_user).sync
  end

  def ensure_org_allows_pages_creation
    return if current_repository.page.present?

    # If the repo is a fork, we need to check the parent repo's org policy
    return render_404 if current_repository.fork? && current_repository.parent&.owner&.organization? && !current_repository.parent&.org_members_can_create_pages?
    render_404 unless current_repository.org_members_can_create_pages?
  end

  def ensure_pages_creation_allowed
    return if current_repository.page.present?

    if current_repository.fork?
      # If the parent repo has a private page, the forked repo cannot have a public page
      return render_404 if !current_repository.can_have_private_pages? && current_repository.parent&.page&.private?

      # A user account can only have a public page.
      # If a repo is forked into a user account page creation is disabled if:
      # * The parent repo has a private page
      # * The parent repo belongs to an org that does not allow public pages
      render_404 if current_repository.owner.user? &&
                  ((current_repository.parent&.owner&.organization? && !current_repository.parent&.org_members_can_create_public_pages?) || current_repository.parent&.page&.private?)
    end
  end

  def operation_prevented_by_soft_deletion?
    current_repository.page&.deleted_at && current_repository.page&.should_soft_delete?
  end

  def ensure_page_not_disabled
    if operation_prevented_by_soft_deletion?
      flash[:error] = "Disabled Pages may not be modified, except to make them visible or destroy them."
      redirect_to redirect_path
    end
  end

  def ensure_repo_has_page
    render_404 unless repo_has_page?
  end

  def repo_has_page?
    return true if current_repository.page&.workflow_build_enabled?

    current_repository.has_gh_pages? && current_repository.page
  end

  def ensure_https_redirect_available
    render_404 unless https_redirect_toggleable?
  end

  def https_redirect_toggleable?
    repo_has_page? && current_repository.page.https_redirect_toggleable?
  end

  def ensure_https_redirect_enabled
    render_404 unless GitHub.pages_https_redirect_enabled?
  end

  def pages_build_types_enabled?
    if GitHub.enterprise?
      return false unless GitHub.actions_enabled?
    end
    true
  end

  def ensure_cname_available
    render_404 unless GitHub.pages_custom_cnames?
  end

  # return cname error message or nil
  # feature flagged
  def cname_error
    message = nil
    if GitHub.pages_custom_cnames?
      # built-in cname validation
      message = current_repository.page.cname_error
      # perform DNS check only if everything else looks peachy
      # note: dns_check may block for up to 2s
      if message.nil? && current_repository.gh_pages_success? && current_repository.page.cname?
        message = dns_check current_repository.page.cname
      end
    end
    message
  end

  # instrumented DNS healthcheck - may block for up to 2s
  def dns_check(cname)
    check = GitHub::Pages::DomainHealthChecker.new(cname)
    return nil if check.valid?

    check.reason.message_with_url
  end

  # If a certificate exists, bump it.
  # If no certificate exists, but the domain is eligible, create it.
  # dns_changed? will update state of the certificate to :dns_changed
  # and issue a new certificate if the existing cert needs a new alt_domain
  def bump_certificate(dns_changed: nil)
    return unless current_repository&.page
    return unless current_repository.page.cname? || current_repository.page.subdomain?

    page = current_repository.page

    if (cert = page.certificate)
      # If alt_domain was added, get a new cert
      if dns_changed
        ActiveRecord::Base.connected_to(role: :writing) do
          cert.update(state: :dns_changed)
        end
        # reload cert so that resume_flow uses the new state
        cert.reload
      end
      cert.resume_flow if !cert.usable? || cert.needs_renewal?
    else
      if page.eligible_for_certificate?
        if page.cname?
          ActiveRecord::Base.connected_to(role: :writing) { page.create_cname_certificate }
        end
      end
    end

    page.reload

    nil
  end
end
