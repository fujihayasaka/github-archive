# typed: false
# frozen_string_literal: true

require "uri"
class Api::RepositoryPages < Api::App
  include ReceiveSchemaWithOpenApi
  include PagesHelper

  DEPLOYMENT_CANCELLED = "deployment_cancelled".freeze
  WORKFLOW_PATH = "dynamic/pages/#{Page::WORKFLOW_NAME}".freeze
  SERVICE_NAME = "repository_pages_api"

  def validate_source_fields(repo, source: nil, build_type: nil, set_default_ref_name: false)
    source_ref_name = source["branch"] if !source.nil? && source.is_a?(Hash)

    source_subdir = source["path"] if !source.nil? && source.is_a?(Hash)
    if !source_subdir.nil? && !Page::VALID_SUBDIRS.include?(source_subdir)
      deliver_error!(400, message: "Invalid source/path value")
    end

    # Set default for the branch name
    if set_default_ref_name && source_ref_name.nil?
      source_ref_name = repo.is_user_pages_repo? ? repo.default_branch : "gh-pages"
    end

    # Set default subdir
    if source_subdir.nil?
      source_subdir = "/"
    end

    [source_ref_name, source_subdir]
  end

  def set_source(page, build_type: nil, source: nil, ref_name: nil, subdir: nil)
    # Set the source
    if !source.nil? && source.is_a?(String)
      case source
      when "master"
        return page.set_source(build_type: build_type, ref_name: "master", subdir: "/")
      when "master /docs"
        return page.set_source(build_type: build_type, ref_name: "master", subdir: "/docs")
      when "gh-pages"
        return page.set_source(build_type: build_type, ref_name: "gh-pages", subdir: "/")
      end
    elsif !ref_name.nil? && !subdir.nil?
      return page.set_source(build_type: build_type, ref_name: ref_name, subdir: subdir)
    else
      return page.set_source(build_type: build_type)
    end

    # No source is set, consider we still saved the page successfully
    true
  end

  class ValidateArtifactUrlError < StandardError; end
  class ValidateArtifactIdError < StandardError; end

  def validate_artifact_url(url, repo)
    if url.nil?
      Failbot.report(ValidateArtifactUrlError.new("No artifact_url provided"))
      # TODO change to no artifact_url or artifact_id provided once pages with actions results artifacts has fully shipped
      # TODO also update description in the app/api/description/operations/repos/create-pages-deployment.yaml since right now it says artifact_url is required but that will change
      deliver_error!(400, message: "No artifact_url provided")
    end

    ## url will look something like this: https://pipelines.actions.githubusercontent.com/e8hcMXr68SdeQnILT3aiw94658skZ5pAwFeS5OBSOdwOCCcxkx/_apis/pipelines/1/runs/1683/artifacts?artifactName=github-pages&%24expand=SignedContent
    ## or https://yimysty-rgogc0h08.service.bpdev-us-east-1.github.net/_services/pipelines/He74m4GoMEEE8Car6quYwFF2wEqEQQBjlPBn6P0c81X4fxnT6l/_apis/pipelines/1/runs/1/artifacts?artifactName=github-pages&%24expand=SignedContent for GHES
    parsed_url = URI.parse(url)
    if GitHub.enterprise?
      if parsed_url.host != GitHub.host_name
        Failbot.report(ValidateArtifactUrlError.new("Invalid artifact url host\nExpected #{GitHub.host_name}\nActual #{parsed_url.host}"))
        deliver_error!(400, message: "Invalid artifact url")
      end
      # Drop port from the URL if we have one since we utilize the runtime URL
      if parsed_url.port
        parsed_url.port = nil
        url = parsed_url.to_s
      end
    else
      unless parsed_url.host.end_with?(".actions.githubusercontent.com")
        Failbot.report(ValidateArtifactUrlError.new("Invalid artifact url host\nExpected *.actions.githubusercontent.com\nActual #{parsed_url.host}"))
        deliver_error!(400, message: "Invalid artifact url")
      end
      # parsed_url.path is /e8hcMXr68SdeQnILT3aiw94658skZ5pAwFeS5OBSOdwOCCcxkx/_apis/pipelines/1/runs/1683/artifacts
      split_path = parsed_url.path.split("/")
      possible_path_error = ValidateArtifactUrlError.new("Invalid artifact url path\nExpected /*/_apis/pipelines/**\nActual #{parsed_url.path}")
      if split_path.length != 8
        Failbot.report(possible_path_error)
        deliver_error!(400, message: "Invalid artifact url")
      elsif split_path[2] != "_apis"
        Failbot.report(possible_path_error)
        deliver_error!(400, message: "Invalid artifact url")
      elsif split_path[3] != "pipelines"
        Failbot.report(possible_path_error)
        deliver_error!(400, message: "Invalid artifact url")
      end
    end

    client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
    resp = client.validate_url(url: url, repository_id: get_global_id(repo))

    if resp.valid != "true"
      Failbot.report(ValidateArtifactUrlError.new("Error returned from pages-deployer\n#{resp.error}"))
      deliver_error!(400, message: "Invalid artifact url")
    end
  end

  def validate_artifact_id(artifact_id, repo)
    if GitHub.enterprise?
      Failbot.report(ValidateArtifactIdError.new("Pages deployments on GHES with artifact_ids are not yet supported"))
      deliver_error!(400, message: "Invalid artifact id")
    end

    artifact = Artifact.where(repository_id: repo.id, id: artifact_id).first
    if artifact.nil?
      Failbot.report(ValidateArtifactIdError.new("Artifact id #{artifact_id} not found for repository #{repo.id} when deploying to pages"))
      deliver_error!(400, message: "Unable to find artifact mathching the id")
    end

    unless artifact.is_results_artifact?
      Failbot.report(ValidateArtifactIdError.new("Artifact id #{artifact_id} not found for repository #{repo.id} when deploying to pages"))
      deliver_error!(400, message: "Artifact type is not supported. Artifact must be created with actions/upload-artifact@v4 or newer")
    end
  end

  def feature_enabled?(feature, repository)
    return false if repository.nil?
    GitHub.flipper[feature].enabled?(repository) || GitHub.flipper[feature].enabled?(repository.owner)
  end

  def pages_build_actions_enabled?(repository)
    if GitHub.enterprise?
      repository&.page&.build_types_enabled?
    else
      true
    end
  end

  def pages_build_actions_odic_validation_enabled?(repository)
    pages_build_actions_enabled?(repository)
  end

  def valid_pages_build_version?(repo, pages_build_version)
    begin
      repo.commits.exist?(pages_build_version)
    rescue RepositoryObjectsCollection::InvalidObjectId
      false
    end
  end

  # To prevent destructive actions on archived repositories, return an
  # early error if the repository is archived
  def find_repo!(even_if_archived: false)
    repo = super()

    if !even_if_archived && repo.archived?
      deliver_error!(409, message: "Repository is archived.")
    end

    repo
  end

  # get page info
  get "/repositories/:repository_id/pages", operation_id: "repos/get-pages" do
    repo = find_repo!(even_if_archived: true)
    control_access :read_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless page = repo.page
    deliver :page_hash, page, {
      repo: repo,
      last_modified: calc_last_modified_for_object(repo),
      html_url: repo.gh_pages_url,
    }
  end

  # create pages site for this repo
  post "/repositories/:repository_id/pages", operation_id: "repos/create-pages-site" do
    repo = find_repo!
    control_access :admin_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if repo.page
      deliver_error!(409, message: "GitHub Pages is already enabled.")
    end

    if repo.private? && !repo.plan_supports_pages?
      deliver_error!(422, message: "Your current plan does not support GitHub Pages for this repository.")
    end

    # Make sure at least public or private pages can be created
    if !repo.org_members_can_create_pages?
      deliver_error!(422, message: "GitHub organization administrators disabled Pages creation.")
    end

    # Returns 422 when creating EMU pages with public visibility
    if repo.is_enterprise_managed? && repo.public?
      deliver_error!(422, message: "Public visibility is not supported for enterprise managed repository pages.")
    end

    # A user repository cannot have a private page , so if it is a user repo and public pages are not allowed, fail
    if GitHub.private_pages_enabled? && GitHub.flipper[:private_pages_org_toggle].enabled?(repo.organization)
      if repo.is_user_pages_repo? && !repo.org_members_can_create_public_pages?
        deliver_error!(422, message: "Organization repositories can only have public pages and public visibility of pages is disabled by organization policy.")
      end
    end

    # A public repository cannot have a private page, so if the repository is public and public pages are not allowed, fail
    if GitHub.flipper[:private_pages_org_toggle].enabled?(repo.organization)
      if repo.public? && !repo.org_members_can_create_public_pages?
        deliver_error!(422, message: "GitHub organization administrators disabled Pages creation.")
      end
    end

    data = receive_with_openapi
    build_type = data["build_type"] unless GitHub.enterprise? && !GitHub.actions_enabled?

    if build_type == "workflow"
      page = repo.build_page(build_type: build_type, source_ref_name: repo.default_branch, source_subdir: "/")
      unless page.save
        deliver_error!(422, message: "Unable to save", errors: page.errors)
      end
    else
      page = repo.build_page

      # Extract and check validity of (new) source value.
      source_ref_name, source_subdir = validate_source_fields(repo, source: data["source"], set_default_ref_name: true)
      deliver_error!(422,
        message: "The #{source_ref_name} branch must exist before GitHub Pages can be built.",
      ) unless repo.heads.include?(source_ref_name)

      # Set the source
      saved = page.save && set_source(page, build_type: build_type, ref_name: source_ref_name, subdir: source_subdir)

      unless saved
        deliver_error!(422, message: "Unable to save", errors: page.errors)
      end
    end

    repo.rebuild_pages(current_user)

    deliver :page_hash, page.reload, {
      status: 201,
      repo: repo,
      last_modified: calc_last_modified_for_object(repo),
      html_url: repo.gh_pages_url,
    }
  end

  # delete pages site for this repo
  delete "/repositories/:repository_id/pages", operation_id: "repos/delete-pages-site" do
    repo = find_repo!
    control_access :admin_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    record_or_404(repo.page)

    receive_with_openapi
    is_user_pages_repo = repo.is_user_pages_repo?
    if is_user_pages_repo || (!is_user_pages_repo && repo.has_gh_pages_branch?)
      deliver_error!(422, message: "Deactivating GitHub pages for this repository is not allowed.")
    elsif !repo.page.destroy
      deliver_error!(422, message: "Unable to deactivate GitHub pages for this repository.", errors: repo.page.errors)
    end

    deliver_empty(status: 204)
  end

  # modify page info
  put "/repositories/:repository_id/pages", operation_id: "repos/update-information-about-pages-site" do
    repo = find_repo!
    control_access :admin_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    page = repo.page
    record_or_404(page)

    data = receive_with_openapi
    attributes = attr(data, :cname, :build_type, :source, :public, :https_enforced)

    # Extract the source attribute (may be a string or a hash)
    source = attributes[:source]

    # Check validity of (legacy) source value. Our current source handling code doesn't do this for us.
    if !source.nil? && source.is_a?(String) && !Page::VALID_SOURCES.include?(source)
      deliver_error!(400, message: "Invalid source value")
    end

    # Extract and check validity of (new) source value.
    source_ref_name, source_subdir = validate_source_fields(repo, source: source) if source.is_a?(Hash)

    # If set pages visibility to private, but plan does not support private pages, return bad request unless in Proxima
    if GitHub.private_pages_enabled? && attributes.key?(:public) && !attributes[:public] && !repo.plan_supports_private_pages?
      deliver_error!(422, message: "Current plan does not support private GitHub Pages")
    end

    # Returns 422 when setting any attribute of a soft-deleted page other than "visibility"
    if repo.page.deleted_at && repo.page.should_soft_delete? && attributes.keys.any? { |attribute| attribute != "public" }
      deliver_error!(422, message: "Page is disabled because current plan does not support private GitHub Pages")
    end

    # Returns 422 when setting private visibility on user repositories
    if GitHub.private_pages_enabled?
      if attributes.key?(:public) && !attributes[:public] && repo.is_user_pages_repo?
        deliver_error!(422, message: "Private visibility is not supported for organization pages.")
      end
    end

    # Returns 422 when setting private visibility on public repositories
    if GitHub.private_pages_enabled?
      if attributes.key?(:public) && !attributes[:public] && repo.public?
        deliver_error!(422, message: "Private visibility is not supported for public repositories.")
      end
    end

    # Returns 422 when setting public visibility on EMU repositories
    if attributes.key?(:public) && attributes[:public] && !repo.can_have_public_pages?
      deliver_error!(422, message: "Public visibility is not supported for enterprise managed repository pages.")
    end

    # Check that custom domains are enabled.
    if attributes.key?(:cname) && !GitHub.pages_custom_cnames?
      deliver_error!(400, message: "Custom domains are not available for GitHub Pages")
    end

    # Check that no custom validation error with the custom domain is present.
    # If a cname is written which is invalid, a before_validation hook clears it from the db silently.
    # This is not ideal behaviour. We want to ensure errors are surfaced to users.
    if attributes.key?(:cname) && page.cname_error(attributes[:cname])
      deliver_error!(400, message: "Invalid cname", errors: [page.cname_error(attributes[:cname])])
    end

    # Check that the organization allows the visibility of page that the user is updating to
    if GitHub.flipper[:private_pages_org_toggle].enabled?(repo.organization) && attributes.key?(:public)
      visibility = attributes[:public] ? :public : :private
      if !repo.org_members_can_create_pages?(visibility: visibility)
        deliver_error!(422, message: "GitHub organization administrators disabled Pages creation.")
      end
    end

    if attributes.key?(:https_enforced)
      deliver_error!(404) unless GitHub.flipper[:pages_health_check].enabled?(repo)
      deliver_error!(404, message: "Custom domains are not available for GitHub Pages") unless GitHub.pages_custom_domain_https_enabled?
      deliver_error!(404, message: "The certificate does not exist yet") if page.certificate.nil?
      deliver_error!(404, message: "The certificate has not finished being issued") if !page.https_available? && !page.certificate&.usable? && page.certificate&.current_state != :new
      deliver_error!(404, message: "Unavailable for your site because a certificate has not yet been issued for your domain") if !page.https_available? && page.eligible_for_certificate?
      deliver_error!(404, message: "Toggling https is disabled") unless page.https_redirect_toggleable?

      page.update_attribute(:https_redirect, attributes[:https_enforced])
    end

    build_type = attributes[:build_type] unless GitHub.enterprise? && !GitHub.actions_enabled?

    # Set the source (if it was set to something)
    unless set_source(page, build_type: build_type, source: source, ref_name: source_ref_name, subdir: source_subdir)
      deliver_error!(422, errors: page.errors)
    end

    page.write_cname(attributes[:cname].to_s, current_user) if attributes.key?(:cname)

    # Switch pages visibilities
    if GitHub.private_pages_enabled? && attributes.key?(:public) && page.public != attributes[:public]
      if repo.adminable_by?(current_user)
        page.update_attribute(:public, attributes[:public])
        # Publish visibility change event to Hydro
        GlobalInstrumenter.instrument "pages.visibility_change", {
          actor: current_user,
          page: page,
          public: page.public
        }
      else
        deliver_error!(422, message: "Only repository admins can change the visibility of GitHub Pages")
      end
    elsif attributes.key?(:public) && !repo.can_have_private_pages?
      deliver_error!(400, message: "Private pages is not enabled for this repository. All Pages will be public.")
    end

    if page.save
      deliver_empty(status: 204)
    else
      deliver_error!(422, errors: page.errors)
    end
  end

  # build page; not currently exposed
  post "/repositories/:repository_id/pages/builds", operation_id: "repos/request-pages-build" do
    receive_with_openapi

    repo = find_repo!
    control_access :build_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    error_message = "The repository does not have a GitHub Pages site. See #{GitHub.developer_help_url}/v3/repos/pages/"
    deliver_error! 403, message: error_message unless repo.has_gh_pages?

    deliver_error! 422, message: "Page is disabled because current plan does not support private GitHub Pages" if repo.page&.deleted_at && repo.page&.should_soft_delete?

    repo.rebuild_pages(current_user)
    pending = { status: "queued", url: "#{@current_url}/latest" }
    deliver_raw pending, status: 201
  end

  # get page builds
  get "/repositories/:repository_id/pages/builds", operation_id: "repos/list-pages-builds" do
    repo = find_repo!
    control_access :read_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    page = repo.page
    record_or_404(page)

    builds = paginate_rel(page.builds)

    pusher_ids = builds.map { |b| b.pusher_id.to_i }
    pusher_ids.uniq!
    pusher_ids.delete 0
    users = (pusher_ids.present? ? User.where(id: pusher_ids) : []).index_by { |u| u.id }
    builds.each do |build|
      build.pusher = users[build.pusher_id]
    end

    deliver :page_build_hash, builds, repo: repo
  end

  # get latest page build
  get "/repositories/:repository_id/pages/builds/latest", operation_id: "repos/get-latest-pages-build" do
    repo = find_repo!
    control_access :read_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless page = repo.page
    deliver_error!(404) unless build = page.builds.first
    deliver :page_build_hash, build, repo: repo, last_modified: calc_last_modified_for_object(build)
  end

  # get single page build
  get "/repositories/:repository_id/pages/builds/:build_id", operation_id: "repos/get-pages-build" do
    repo = find_repo!
    control_access :read_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless page = repo.page
    deliver_error!(404) unless build = page.builds.find_by_id(int_id_param!(key: :build_id))
    deliver :page_build_hash, build, repo: repo, last_modified: calc_last_modified_for_object(build)
  end

  # DNS health check for cname
  get "/repositories/:repository_id/pages/health", operation_id: "repos/get-pages-health-check" do
    repo = find_repo!(even_if_archived: true)
    control_access :admin_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless GitHub.flipper[:pages_health_check].enabled?(repo)

    page = repo.page
    record_or_404(page)

    if !GitHub.pages_custom_cnames?
      deliver_error!(400, message: "Custom domains are not available for GitHub Pages")
    end

    deliver_error!(422, message: "There isn't a cname for this page.") if !page.cname?

    operation_result = Pages::KV.store.get(page.dns_kv_key).value!
    if operation_result.present?
      deliver :pages_health_check_hash, JSON.parse(operation_result), status: 200
    else
      job_status = Pages::KV.store.get(page.job_status_kv_key).value!
      if !job_status.present?
        ActiveRecord::Base.connected_to(role: :writing) do
          Pages::KV.store.set(page.job_status_kv_key, "queued", expires: 2.minutes.from_now)
        end
        PagesDnsHealthCheckJob.perform_later(page.id)
      end
      deliver_empty status: 202
    end
  end

  # create deployment with deployment id
  def create_deployment_common_deployment_id(repo)
    page = repo.page

    # TODO create the page model when the page does not exists
    deliver_error!(404) unless page

    deliver_error!(422, message: "Page is disabled because current plan does not support private GitHub Pages") if page.deleted_at && page.should_soft_delete?

    data = receive_with_openapi

    preview = data["preview"] && feature_enabled?(:pages_preview_deployments, repo)

    preview_token = ""

    if GitHub.actions_results_core_address.present? && data["artifact_id"].present?
      validate_artifact_id(data["artifact_id"], repo)
    elsif data["artifact_url"].present?
      validate_artifact_url(data["artifact_url"], repo)
    else
      deliver_error!(400, message: "Missing both fields `artifact_id` and `artifact_url`. At least one is required to create a deployment.")
    end

    pages_build_version = data["pages_build_version"]

    # TODO: Refactor this to  for pages_build_version instead of deployment_id
    deliver_error!(404) unless valid_pages_build_version?(repo, pages_build_version)

    ref = page.source_branch

    if pages_build_actions_odic_validation_enabled?(repo)
      oidc_token = data["oidc_token"]
      payload, error = validate_actions_jwt_token(oidc_token, repo)
      if payload.nil?
        GitHub.dogstats.increment "pages.deployment.badrequest", tags: ["reason:invalid_oidc_token"]
        deliver_error!(400, message: "Invalid actions OIDC token due to #{error}, validate around #{Time.now.to_i}.")
      end

      # Get the reference and commit SHA from the OIDC token
      ref = payload["ref"] if preview || page.workflow_build_enabled?
      ref = ref["refs/heads/".length..] if ref.start_with?("refs/heads/")

      # If handling a "pull_request_target" event, get the reference and commit SHA from the pull request metadata
      # to avoid accidentally deploying the base branch
      if preview && payload["event_name"] == "pull_request_target"
        workflow_run = Actions::WorkflowRun.where(id: payload["run_id"].to_s, repository_id: repo.id).first
        pull_request = workflow_run.trigger
        ref = pull_request.merge_ref
      end
      # the oidc token validation gonna ensure the environment exists, environment name is case-insensitive.
      # check the environment does have any protect branch policy.
      # skip the source_branch if the environment is protected by anything or the build type is workflow.
      # TODO: we should update this re:previews
      unless page.build_type == "workflow" || valid_deployment_branch?(repo, page, payload)
        GitHub.dogstats.increment "pages.deployment.badrequest", tags: ["reason:invalid_branch"]
        deliver_error!(400, message: "Invalid deployment branch and no branch protection rules set in the environment. Deployments are only allowed from #{page.source_branch}")
      end
      deployment = page.create_or_find_deployment_for(ref)
      deployment.update_attribute(:check_run_id, payload["run_id"])
    else
      deployment = page.create_or_find_deployment_for(ref)
    end

    deployment_id = deployment.id

    GitHub.dogstats.increment "pages.deployment", tags: ["build_type:#{page.build_type}"]

    client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
    begin
      ongoing_deployment_id = client.request_deployment(deployment_id: deployment_id, repository_id: repo.id, ref: ref)
    rescue
      deliver_error(500, message: "Could not find deployment")
    end

    if ongoing_deployment_id.to_s != deployment_id.to_s
      GitHub.dogstats.increment "pages.deployment.badrequest", tags: ["reason:ongoing_deployment"]
      deliver_error!(400, message: "Deployment request failed for #{deployment_id} due to in progress deployment. Please cancel #{ongoing_deployment_id} first or wait for it to complete.")
    end

    replicator = GitHub::Pages::Replicator.new(repo, preview)
    hosts = if GitHub.multi_tenant_enterprise?
      # mutli-tenant enterprise, we will rely on replicator in pages-deployer.
      []
    else
      # looking for deployments host
      # The original code is using round robin to determine hosts. As long as build id is is n times of dfs node, it works the same.
      # not to be confused with the Pages::Build id
      replicator_build_id = rand(0..100)
      replicator.hosts_with_datacenter(replicator_build_id)
    end

    payload = {
      hosts: hosts,
      path: GitHub::Routing.dpages_storage_path(page.id, revision: pages_build_version),
      artifact_url: data["artifact_url"],
      environment: data["environment"] || "github-pages",
      pages_build_version: pages_build_version,
      deployment_id: deployment_id,
      global_id: get_global_id(repo),
      repo_id: repo.id,
      owner_id: repo.owner_id,
      writing_non_voting: replicator.write_non_voting_replicas?,
      ref: ref,
      preview: preview,
      preview_token: preview_token,
    }

    if GitHub.actions_results_core_address.present? && data["artifact_id"].present?
      payload[:artifact_id] = data["artifact_id"]
    end

    # append additional payload for multi-tenant enterprise (proxima)
    if GitHub.multi_tenant_enterprise?
      payload[:subdomain] = page.display_subdomain
      payload[:page_id] = page.id
      payload[:tenant] = GitHub::CurrentTenant.get&.slug
      payload[:tenant_id] = GitHub::CurrentTenant.get&.id
      payload[:custom_subdomain] = page.display_custom_subdomain
      payload[:public] = page.public?
    end

    # sending to review-lab environment if the repo within paper-spa organization on dotcom
    queue_name = (repo.owner.name == "paper-spa" && !GitHub.enterprise?) ? "pages-deployer-review-lab" : "pages-deployer"
    GitHub::Pages::PagesDeployerClient.enqueue(payload, queue_name)

    # TODO deployment_queued should be stored as constant
    begin
      client.update_status(deployment_id: deployment_id, repository_id: repo.id, status: "deployment_queued")
    rescue
      deliver_error!(500, message: "Could not update the status of the environment")
    end

    return_hash = {
      deployment_id: deployment_id,
      page_url: page.url.to_s,
      repository: repo,
      preview_url: ""
    }

    if preview
      deployment_token = deployment.token
      return_hash[:preview_url] = "#{page.url.scheme}://#{repo.owner.login_for_api}-#{deployment_token}-#{page.id}.drafts.github.io/"
    end

    deliver :pages_deployment_hash, return_hash, status: 200
  end

  # Extract common logic in the "create deployment" endpoint while we support both old and new routes
  def create_deployment_common(repo)
    page = repo.page

    # TODO create the page model when the page does not exists
    deliver_error!(404) unless page

    deliver_error!(422) if page.deleted_at && page.should_soft_delete?

    data = receive_with_openapi

    preview = data["preview"] && feature_enabled?(:pages_preview_deployments, repo)

    preview_token = ""

    if GitHub.actions_results_core_address.present? && data["artifact_id"].present?
      validate_artifact_id(data["artifact_id"], repo)
    elsif data["artifact_url"].present?
      validate_artifact_url(data["artifact_url"], repo)
    else
      deliver_error!(400, message: "Missing both fields `artifact_id` and `artifact_url`. At least one is required to create a deployment.")
    end

    # deployment id used to track deployment
    deployment_id = data["pages_build_version"]

    deliver_error!(404) unless valid_pages_build_version?(repo, deployment_id)

    GitHub.dogstats.increment "pages.deployment", tags: ["build_type:#{page.build_type}"]

    ref = page.source_branch

    # verify oidc_token, and check deployment branch matches
    if pages_build_actions_odic_validation_enabled?(repo)
      oidc_token = data["oidc_token"]
      payload, error = validate_actions_jwt_token(oidc_token, repo)
      if payload.nil?
        GitHub.dogstats.increment "pages.deployment.badrequest", tags: ["reason:invalid_oidc_token"]
        deliver_error!(400, message: "Invalid actions OIDC token due to #{error}, validate around #{Time.now.to_i}.")
      end

      # Get the reference and commit SHA from the OIDC token
      ref = payload["ref"] if preview || page.workflow_build_enabled?
      ref = ref["refs/heads/".length..] if ref.start_with?("refs/heads/")

      if preview
        deployment_id = payload["sha"]

        # If handling a "pull_request_target" event, get the reference and commit SHA from the pull request metadata
        # to avoid accidentally deploying the base branch
        if payload["event_name"] == "pull_request_target"
          workflow_run = Actions::WorkflowRun.where(id: payload["run_id"].to_s, repository_id: repo.id).first
          pull_request = workflow_run.trigger
          ref = pull_request.merge_ref
          deployment_id = pull_request.head_sha
        end
      end

      # the oidc token validation gonna ensure the environment exists, environment name is case-insensitive.
      # check the environment does have any protect branch policy.
      # skip the source_branch if the environment is protected by anything or the build type is workflow.
      # TODO: we should update this re:previews
      unless page.build_type == "workflow" || valid_deployment_branch?(repo, page, payload)
        GitHub.dogstats.increment "pages.deployment.badrequest", tags: ["reason:invalid_branch"]
        deliver_error!(400, message: "Invalid deployment branch and no branch protection rules set in the environment. Deployments are only allowed from #{page.source_branch}")
      end

      # create or find deployment based on ref. (ensure deployment object exists)
      deployment = page.create_or_find_deployment_for(ref)
      deployment.update_attribute(:check_run_id, payload["run_id"])
    end

    client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
    ongoing_deployment_id = client.request_deployment(deployment_id: deployment_id, repository_id: repo.id, ref: ref)
    if ongoing_deployment_id != deployment_id
      GitHub.dogstats.increment "pages.deployment.badrequest", tags: ["reason:ongoing_deployment"]
      deliver_error!(400, message: "Deployment request failed for #{deployment_id} due to in progress deployment. Please cancel #{ongoing_deployment_id} first or wait for it to complete.")
    end

    replicator = GitHub::Pages::Replicator.new(repo, feature_enabled?(:pages_preview_deployments, repo) && data["preview"])
    hosts = if GitHub.multi_tenant_enterprise?
      # mutli-tenant enterprise, we will rely on replicator in pages-deployer.
      []
    else
      # looking for deployments host
      # The original code is using round robin to determine hosts. As long as build id is is n times of dfs node, it works the same.
      # not to be confused with the Pages::Build id
      replicator_build_id = rand(0..100)
      replicator.hosts_with_datacenter(replicator_build_id)
    end

    payload = {
      hosts: hosts,
      path: GitHub::Routing.dpages_storage_path(page.id, revision: deployment_id),
      artifact_url: data["artifact_url"],
      environment: data["environment"] || "github-pages",
      pages_build_version: deployment_id,
      global_id: get_global_id(repo),
      repo_id: repo.id,
      owner_id: repo.owner_id,
      writing_non_voting: replicator.write_non_voting_replicas?,
      ref: ref,
      preview: preview,
      preview_token: preview_token,
    }

    if GitHub.actions_results_core_address.present? && data["artifact_id"].present?
      payload[:artifact_id] = data["artifact_id"]
    end

    # append additional payload for multi-tenant enterprise (proxima)
    if GitHub.multi_tenant_enterprise?
      payload[:subdomain] = page.display_subdomain
      payload[:page_id] = page.id
      payload[:tenant] = GitHub::CurrentTenant.get&.slug
      payload[:tenant_id] = GitHub::CurrentTenant.get&.id
      payload[:custom_subdomain] = page.display_custom_subdomain
      payload[:public] = page.public?
    end

    # sending to review-lab environment if the repo within paper-spa organization on dotcom
    queue_name = (repo.owner.name == "paper-spa" && !GitHub.enterprise?) ? "pages-deployer-review-lab" : "pages-deployer"
    GitHub::Pages::PagesDeployerClient.enqueue(payload, queue_name)

    # TODO deployment_queued should be stored as constant
    client.update_status(deployment_id: deployment_id, repository_id: repo.id, status: "deployment_queued")

    return_hash = {
      deployment_id: deployment_id,
      page_url: page.url.to_s,
      repository: repo,
      preview_url: ""
    }

    if preview
      deployment_token = deployment.token
      return_hash[:preview_url] = "#{page.url.scheme}://#{repo.owner.login_for_api}-#{deployment_token}-#{page.id}.drafts.github.io/"
    end

    deliver :pages_deployment_hash, return_hash, status: 200
  end

  post "/repositories/:repository_id/pages/deployment", operation_id: :unreleased do
    repo = find_repo!
    deliver_error!(404) unless pages_build_actions_enabled?(repo)
    control_access :write_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.increment "pages.renamed_api_routes", tags: ["operation:create_deployment", "route:legacy"]
    if GitHub.flipper[:deployment_id_tracking].enabled?(repo) || GitHub.flipper[:deployment_id_tracking].enabled?(repo.owner)
      create_deployment_common_deployment_id(repo)
    else
      create_deployment_common(repo)
    end
  end
  post "/repositories/:repository_id/pages/deployments", operation_id: "repos/create-pages-deployment" do
    repo = find_repo!
    deliver_error!(404) unless pages_build_actions_enabled?(repo)
    control_access :write_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.increment "pages.renamed_api_routes", tags: ["operation:create_deployment", "route:restful"]
    if GitHub.flipper[:deployment_id_tracking].enabled?(repo) || GitHub.flipper[:deployment_id_tracking].enabled?(repo.owner)
      create_deployment_common_deployment_id(repo)
    else
      create_deployment_common(repo)
    end
  end

  # Extract common logic in the "get deployment status" endpoint while we support both old and new routes
  def get_deployment_common(repo)
    page = repo.page
    deliver_error!(404) unless page

    # looking current pages deployment
    deployment_id = params[:deployment_id]

    if GitHub.flipper[:deployment_id_tracking].enabled?(repo) || GitHub.flipper[:deployment_id_tracking].enabled?(repo.owner)
      deployment = Page::Deployment.where(id: deployment_id, page_id: page.id).where.not(revision: nil).first
    else
      deployment = Page::Deployment.where(revision: deployment_id, page_id: page.id).first
    end

    # if the revision not match the current deployment version or did not have final deployment status, check if we have ongoing deployment.
    if deployment.nil?
      # TODO check to memoize client
      client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
      resp = client.get_status(deployment_id: deployment_id, repository_id: repo.id, owner_id: repo.owner_id)
      deliver :pages_deployment_status_hash, {
        status: resp
      }, status: resp == "not_found" ? 404 : 200
    else
      deliver :pages_deployment_status_hash, {
        status: "succeed"
      }, status: 200
    end
  end

  # update id following this process when ready: https://github.com/github/github/pull/192461/files#file-test-fast-linting-api_operation_id_test-rb-L126
  # get pages deployment status
  get "/repositories/:repository_id/pages/deployment/status/:deployment_id", operation_id: :unreleased do
    repo = find_repo!(even_if_archived: true)
    deliver_error!(404) unless pages_build_actions_enabled?(repo)
    control_access :get_repository_pages_deployment_status,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.increment "pages.renamed_api_routes", tags: ["operation:get_deployment", "route:legacy"]
    get_deployment_common(repo)
  end
  get "/repositories/:repository_id/pages/deployments/:deployment_id", operation_id: "repos/get-pages-deployment" do
    repo = find_repo!(even_if_archived: true)
    deliver_error!(404) unless pages_build_actions_enabled?(repo)
    control_access :get_repository_pages_deployment_status,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.increment "pages.renamed_api_routes", tags: ["operation:get_deployment", "route:restful"]
    get_deployment_common(repo)
  end

  # Extract common logic in the "cancel deployment" endpoint while we support both old and new routes
  def cancel_deployment_common(repo)
    page = repo.page
    deliver_error!(404) unless page

    deployment_id = params[:deployment_id]
    deliver_error!(404) unless valid_pages_build_version?(repo, deployment_id)

    client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)
    client.update_status(deployment_id: deployment_id, repository_id: repo.id, status: DEPLOYMENT_CANCELLED)

    # looking if the pages deployment already succeed
    deployment = page.deployment_for(page.source_branch)
    if deployment&.revision == deployment_id
      client.clear_status(deployment_id: deployment_id, repository_id: repo.id)
      deliver_error!(400, message: "Unable to cancel deployment #{deployment_id} as it's finished.")
    else
      page.fail_build
    end
    deliver_empty status: 204
  end

  # When tracking with deployment id
  def cancel_deployment_common_deployment_id(repo)
    page = repo.page
    deliver_error!(404) unless page

    deployment_id = params[:deployment_id]
    pages_build_version = page.repository.heads.find(page.source_branch)&.target.oid
    deliver_error!(404) unless valid_pages_build_version?(repo, pages_build_version)

    client = Page::Twirp::RequestClient.new(service_name: SERVICE_NAME)

    begin
      client.update_status(deployment_id: deployment_id, repository_id: repo.id, status: DEPLOYMENT_CANCELLED)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::Error => e
      Failbot.report(e, {
        "gh.pages.deployment.id" => deployment_id,
        "gh.repo.id" => repo.id
        })
      deliver_error!(404, message: "Invalid deployment id")
    end

    # looking if the pages deployment already succeed
    deployment = page.deployment_for(page.source_branch)
    if deployment&.revision == deployment_id
      client.clear_status(deployment_id: deployment_id, repository_id: repo.id)
      deliver_error!(400, message: "Unable to cancel deployment #{deployment_id} as it's finished.")
    else
      page.fail_build
    end
    deliver_empty status: 204
  end

  # update id following this process when ready: https://github.com/github/github/pull/192461/files#file-test-fast-linting-api_operation_id_test-rb-L126
  # cancel deployment by deployment id
  put "/repositories/:repository_id/pages/deployment/cancel/:deployment_id", operation_id: :unreleased do
    repo = find_repo!
    deliver_error!(404) unless pages_build_actions_enabled?(repo)
    control_access :write_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.increment "pages.renamed_api_routes", tags: ["operation:cancel_deployment", "route:legacy"]
    if GitHub.flipper[:deployment_id_tracking].enabled?
      cancel_deployment_common_deployment_id(repo)
    else
      cancel_deployment_common(repo)
    end
  end
  post "/repositories/:repository_id/pages/deployments/:deployment_id/cancel", operation_id: "repos/cancel-pages-deployment" do
    repo = find_repo!
    deliver_error!(404) unless pages_build_actions_enabled?(repo)
    control_access :write_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    GitHub.dogstats.increment "pages.renamed_api_routes", tags: ["operation:cancel_deployment", "route:restful"]
    if GitHub.flipper[:deployment_id_tracking].enabled?
      cancel_deployment_common_deployment_id(repo)
    else
      cancel_deployment_common(repo)
    end
  end

  # enable telemetry for a desired workflow run
  post "/repositories/:repository_id/pages/telemetry", operation_id: "repos/telemetry" do
    repo = find_repo!
    deliver_error!(404) unless pages_build_actions_enabled?(repo)

    page = repo.page
    deliver_error!(404, message: "failed to resolve repository to a page") unless page

    deliver_error!(404, message: "page is disabled") if page.deleted_at && page.should_soft_delete?

    # To ensure we do not ingest arbitrary data, we validate that the `GITHUB_RUN_ID`
    # belongs to the repository scoped to the actor before accepting any input.
    control_access :write_pages,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    workflow_run_id = data["github_run_id"]

    # Lookup the workflow run
    begin
      workflow_run = Actions::WorkflowRun.find(workflow_run_id)
    rescue ActiveRecord::RecordNotFound
      deliver_error!(404,
        message: "failed to find requested workflow run",
      ) unless workflow_run.present?
    end

    # We also validate that the `GITHUB_RUN_ID` belongs to the resolved repository
    deliver_error!(422,
      message: "failed to resolve workflow run to requested repository",
    ) unless workflow_run.repository.id == repo.id


    # We only want the builds that we control to contribute to our SLOs or
    # trigger alerting. To ensure this, we validate that the telemetry received
    # matches build & deploy jobs that we initiate. The provided workflow run ID
    # is mapped to a unique identifier that matches our expected build Action.
    if workflow_run.workflow.path != WORKFLOW_PATH
      # FIXME: silently ignore request until we need telemetry for Actions
      # we do not support
      return deliver_empty status: 200
    end

    # Validation has completed. Publish metrics using the workflow metadata
    # found by resolving a `GITHUB_RUN_ID` to a workflow.
    # TODO: cache result similar to /repositories/:repository_id/pages/health
    # to avoid publishing the same metrics multiple times
    build_workflow = workflow_run
      .latest_jobs
      .sort { |a, b| a.started_at <=> b.started_at }
      .first # assume the build job is always started first

    # Note: when the database is lagging behind, we may not have a build_workflow available,
    # so we lean in on the data we extract from the step calling this API instead.

    # We post `conclusion` from the result of the previous workflow build job. There is no reason
    # to expect that we could find the conclusion from the workflow database record if it is not
    # already present in the request body, but we check anyway for the sake of thoroughness.
    conclusion = data["conclusion"].presence || build_workflow&.conclusion
    annotations = nil
    log_fields = {
      "code.namespace" => self.class.name,
      "code.function" => "telemetry",
      "gh.catalog_service" => "github/pages",
      "gh.repo.id" => repo.id,
      "gh.pages.workflow.run.id" => workflow_run_id
    }
    if conclusion.nil? || conclusion == "failure"
      annotations = build_workflow&.annotations.map do |a|
        a.message
      end.join("\n") if build_workflow&.annotations
      GitHub.logger.info("Pages build workflow conclusion is #{conclusion || 'nil'}", log_fields.merge({
        "gh.pages.annotations" => annotations
      }))
    end

    # Logging
    conclusion = "skipped" if skip_report_build_error?(annotations)
    tags = [
      "conclusion:#{conclusion}",
    ]
    GitHub.dogstats.increment "pages.workflows.build", tags: tags
    GitHub.dogstats.distribution "pages.workflows.build.duration", (build_workflow&.duration || 0), tags: tags
    deliver_empty status: 200

  end

  private

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end

  def valid_deployment_branch?(repo, page, payload)
    environment_class_name, environment_id = begin
      Platform::Helpers::NodeIdentification.from_global_id(payload["environment_node_id"])
    rescue Platform::Errors::NotFound
      nil
    end

    if environment_class_name != Environment.name
      # This would only happen if the JWT's "environment_nod_id" field was an invalid global ID,
      # or was an ID for something other than an Environment.
      if payload["environment_node_id"].blank?
        GitHub.logger.error("Invalid environment_node_id: blank", {
          "gh.environment.global_id": payload["environment_node_id"].inspect,
        })
        deliver_error!(400, message: <<~TEXT)
          Missing environment. Ensure your workflow's deployment job has an environment. Example:
          jobs:
            deploy:
              environment:
                name: github-pages
          TEXT
      else
        GitHub.logger.error("Invalid environment_node_id, does not decode to class #{Environment.name}", {
          "gh.environment.global_id": payload["environment_node_id"],
          "gh.environment.actual_class_name": environment_class_name,
        })
        deliver_error!(500, message: "Invalid environment node id")
      end
    end

    unless Environment.where(repository_id: repo.id, id: environment_id).last&.gates&.any?
      if payload["ref"] != "refs/heads/#{page.source_branch}"
        return false
      end
    end
    true
  end
end
