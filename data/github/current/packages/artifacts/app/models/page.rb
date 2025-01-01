# typed: false
# frozen_string_literal: true

require "digest/sha1"
require "github/pages/domain_health_checker"
require_relative "pages/k_v"
class Page < ApplicationRecord::Pages

  VALID_SOURCES = ["gh-pages", "master", "master /docs"].freeze
  VALID_LEGACY_BRANCHES = %w[master gh-pages].freeze
  VALID_SUBDIRS = ["/", "/docs"].freeze
  WORKFLOW_NAME = "pages-build-deployment".freeze
  ARTIFACT_NAME = "github-pages"
  ENVIRONMENT_NAME = "github-pages"
  SOFT_DELETION_LIMIT = 90.days

  class PageError < StandardError; end

  class PageBuildFailed < PageError; end
  class InvalidCNAME < PageError; end
  class InvalidCustomSubdomain < PageError; end
  class RunDynamicWorkflowError < PageError; end
  class NullDomainMatch < PageError; end

  include GitHub::CacheLock
  include Instrumentation::Model
  include PagesHelper

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  scope :with_domain_match, -> (domain_name) {

    if domain_name.nil?
      Failbot.report(NullDomainMatch.new("Nil is not a valid domain name to match on."))
      next none
    end

    where(cname: domain_name)
      .or(where(parent_domain: domain_name))
      .or(where(www_parent_domain: domain_name))
  }

  has_many :deployments, -> { order("updated_at desc") }, dependent: :delete_all

  has_many :builds, -> { order("updated_at desc") }
  destroy_dependents_in_background :builds

  enum :build_type, {
    legacy: 0,
    workflow: 1,
  }

  validate :ensure_soft_deleted_page_has_no_cname
  validate :ensure_live_page_has_no_deleted_cname

  before_validation :set_repository_page, on: :create
  before_validation :set_cname, unless: :staged_change_to_deleted_at?
  before_validation :set_404
  before_validation :set_https_redirect
  before_validation :set_hsts_max_age
  before_validation :validate_legacy_source, unless: :workflow_build_enabled?
  before_create :set_visibility
  before_create :initialize_source_fields, unless: :workflow_build_enabled?
  before_update :legacy_backport_source_fields, unless: :workflow_build_enabled?
  after_create :track_page_creation # rubocop:todo GitHub/AfterCommitCallbackInstrumentation
  before_destroy :generate_webhook_payload_for_deletion # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :destroy_dependent_pages_replicas
  after_destroy :instrument_destroy
  after_update :instrument_https_redirect_toggled, if: :saved_change_to_https_redirect?
  after_update :instrument_cname, if: :saved_change_to_cname?
  after_update :instrument_source, if: :saved_change_to_source_fields?
  after_create :instrument_visibility
  after_update :instrument_visibility, if: :saved_change_to_public?
  after_update :instrument_deleted_at, if: :saved_change_to_deleted_at?

  after_create :instrument_build_type
  after_update :instrument_build_type, if: :saved_change_to_build_type?

  after_commit :create_certificate_in_background, if: proc { cname? && saved_change_to_cname? }, on: [:create, :update]
  after_create :set_subdomain_on_create
  after_update :set_subdomain_to_match_visibility, if: :saved_change_to_public?
  after_create :set_environment
  after_update :set_environment, if: proc { saved_change_to_source_fields? || saved_change_to_build_type? }

  after_update :restore_deleted, if: :should_restore_deleted_after_changing_visibility?

  after_update :add_proxima_record_on_update, if: :should_emit_page_update_record_on_update?
  after_update :add_proxima_record_on_update_subdomain, if: :should_emit_page_update_record_on_update_subdomain?
  after_update :add_proxima_record_on_delete, if: :should_emit_page_deletion_record_on_update?
  after_destroy :add_proxima_record_on_delete, if: -> { GitHub.multi_tenant_enterprise? }

  after_commit :instrument_update

  # We rely on Owner a lot, which goes through repository, so lets delegate
  delegate :owner, to: :repository

  attribute :source_ref_name, StringFromBinary.new

  def async_owner
    async_repository.then do |repository|
      next unless repository
      repository.async_owner
    end
  end

  def target_for_conditional_access
    owner
  end

  # Reset memoized variables on reload. Defined in ApplicationRecord::Base, called in #reload.
  def reset_memoized_attributes
    [
      :@async_primary,
      :@async_https_available,
      :@async_https_redirect_required,
      :@async_certificate,
      :@certificate,
      :@async_certificate_domain,
      :@certificate_domain,
    ].each do |instance_var|
      remove_instance_variable(instance_var) if instance_variable_defined?(instance_var)
    end
  end

  # Returns true if the page visibility has been set to private
  def private?
    !public?
  end

  def build_types_enabled?
    if GitHub.enterprise?
      return false unless GitHub.actions_enabled?
    end
    true
  end

  def workflow_build_enabled?
    build_types_enabled? && self.build_type == "workflow"
  end

  # Determine if this is a user pages repository. User pages repositories are
  # named like "<user>.github.com"(v1) or "<user>.github.io"(v2) and are published
  # to the root of the user's namespace. User pages do not exist in Proxima so
  # primary? will return false if GitHub.multi_tenant_enterprise.
  #
  # Returns a boolean.
  def primary?
    async_primary?.sync
  end

  def async_primary?
    return @async_primary if defined?(@async_primary)

    @async_primary = async_repository.then do |repository|
      next false unless repository
      repository.async_is_user_pages_repo?
    end
  end

  def async_source_branch
    # Use new source_ref_name logic if available (and feature flagged)
    if source_ref_name
      Promise.resolve(source_ref_name)

    # Use legacy logic
    elsif source == "master" || source == "master /docs"
      Promise.resolve("master")
    else
      # Legacy AND new initialization logic
      # The legacy logic used to hardcode `master` instead of the default branch here. This is a deliberate
      # change for the best. A legacy repo will still have its default branch set to `master` thus not breaking
      # legacy behavior.
      # If a legacy repository (user/project repo only) changes its default branch, subsequent Pages will build
      # off the default branch. The UX documents that changing the default branch of a repo may
      # have unintended consequences ; this is one of them.
      async_primary?.then { |is_primary| is_primary ? repository.default_branch : "gh-pages" }
    end
  end

  # The branch name for Pages builds.
  def source_branch
    async_source_branch.sync
  end

  # The source directory for Pages builds.
  def source_dir
    return source_subdir if source_subdir

    if source == "master /docs"
      "/docs"
    else
      "/"
    end
  end

  # True if a source with a non-root subdir is configured for Pages builds
  def subdir_source?
    source_dir != "/"
  end

  # Validate the legacy source value before validation
  def validate_legacy_source
    if source != "master" && source != "master /docs"
      self.source = nil
    end
  end

  def ignore_blob_cname?
    build_types_enabled? && build_type == "workflow"
  end

  # Set the source from which to build a page
  #
  # Source should be set to nil and only ref_name and subdir should be passed
  def set_source(source: nil, build_type: nil, ref_name: nil, subdir: nil)
    if !ref_name.nil? && !subdir.nil?
      # Set a backward compatible value for source (in case we disable the feature flag)
      if ref_name == "master" && subdir == "/"
        write_attribute :source, "master"
      elsif ref_name == "master" && subdir == "/docs"
        write_attribute :source, "master /docs"
      else
        # Note: this value is not necessarily correct if ref_name was a total arbitrary branch
        # that means in theory if we were to use this field again, we would need to rebuild the page
        write_attribute :source, nil
      end
      # Update the source fields
      write_attribute :source_ref_name, ref_name
      write_attribute :source_subdir, subdir

    # Use legacy logic for setting the source (and source only) - this will call the before create/update callbacks
    elsif source == "master" || source == "master /docs"
      write_attribute :source, source
    elsif source
      write_attribute :source, nil
    end

    write_attribute :build_type, build_type unless build_type.nil?

    # Finally save the model once (calling update_attribute for each field would call the callbacks multiple times and meddle with the value)
    save
  end

  # clean page
  def clear_source
    @clear_source = true
    write_attribute :source, nil
    write_attribute :source_ref_name, nil
    write_attribute :source_subdir, nil
    save
  end

  ##
  # Initializes the source_ref_name and source_subdir fields if they are not already set.
  #
  # This is intended to be used for newly-created Page objects prior to saving in the DB.
  #
  def initialize_source_fields
    # Skip this altogether if the feature flag is set and the two fields were initialized already
    return unless self.source_ref_name.nil? || self.source_subdir.nil?

    self.source_ref_name = self.source_branch
    self.source_subdir = self.source_dir
  end

  # Initialize github-pages environment.
  # This is triggered by hook after_create.
  def set_environment
    return unless build_types_enabled?
    return if build_type == "legacy" && source_ref_name.blank?

    begin
      environment = repository.environments.includes(:gates).find_by(name: ENVIRONMENT_NAME) || Environment.create_for_repository(repository.id, ENVIRONMENT_NAME)

      # check if any gates exist, if not created it with protected branches
      # use explicitly branch protection type
      environment.create_branch_policy_gate(protected_branch_policy: false) unless environment.gates&.any?

      protection_ref = build_type == "workflow" ? repository.default_branch : source_ref_name

      environment.branch_policy_gate&.branch_policies&.create(name: protection_ref, repository: repository) unless protection_ref.nil?
    rescue Environment::EnvironmentError, ActiveRecord::RecordInvalid => e
      Failbot.report(e)
    end
  end

  # TODO return the actual pages deployment environment
  def environment
    ENVIRONMENT_NAME
  end

  # Prior the pages_any_branch feature flag, initialize the following two columns in the model:
  # - source_ref_name
  # - source_subdir
  #
  # Using values matching the current source field.
  def legacy_backport_source_fields
    # Skip this altogether if the feature flag is set and the two fields were initialized already
    return unless self.source_ref_name.nil? || self.source_subdir.nil?

    # Skip this if it's for clear source.
    return if @clear_source

    # On a project/user page, only master and / are allowed (source is nil)
    if primary?
      self.source_ref_name = "master"
      self.source_subdir = "/"

    # master and /
    elsif self.source == "master"
      self.source_ref_name = "master"
      self.source_subdir = "/"

    # master and /docs
    elsif self.source == "master /docs"
      self.source_ref_name = "master"
      self.source_subdir = "/docs"

    # gh-pages and / (source is nil)
    else
      self.source_ref_name = "gh-pages"
      self.source_subdir = "/"
    end
  end

  # Do we have a certificate for serving HTTPS requests for this page?
  #
  # Returns Promise which resolves to a boolean.
  def async_https_available?
    return Promise.resolve(false) unless GitHub.pages_https_redirect_enabled?

    url.async_host.then do |url_host|
      next true if GitHub.pages_https_domains.include?(url_host)

      url.async_pages_host_name.then do |url_pages_host_name|
        next true if url_host.ends_with?(".#{url_pages_host_name}")

        async_certificate.then do |certificate|
          !!certificate&.usable?  # double bang in case this result can make it back
          # to the platform interface which is probably expecting a boolean, not a boolean-ish
        end
      end
    end
  end

  def https_available?
    async_https_available?.sync
  end

  # Is it required that this Page have https_redirect enabled?
  #
  # Returns a Promise which resolves to a boolean.
  def async_https_redirect_required?
    return Promise.resolve(false) unless GitHub.pages_https_redirect_enabled?

    url.async_host.then do |url_host|
      next true if url_host.ends_with? ".#{GitHub.pages_host_name_v1}"
      next false unless url_host.ends_with?(".#{GitHub.pages_host_name_v2}") || GitHub.pages_https_domains.include?(url_host)

      async_https_required_for_repository?.then do |https_required|
        next async_https_available? if https_required

        false
      end
    end
  end

  def https_redirect_required?
    async_https_redirect_required?.sync
  end

  # If HTTPS is required for the repository due to the time it was created.
  #
  # Returns a Promise which resolves to a Boolean value.
  # The feature flag must be enabled, and the repository must have been
  # created after the given date where we began requiring this.
  def async_https_required_for_repository?
    async_repository.then do |repository|
      next false unless repository
      repository.created_at > GitHub.pages_https_required_after
    end
  end

  # Can the owner toggle HTTPS redirects for this repo?
  #
  # Returns boolean.
  def https_redirect_toggleable?
    https_available? && !https_redirect_required?
  end

  # Is HSTS required for this site?
  #
  # Returns boolean.
  def hsts_required?
    https_redirect_required? && owner.created_at > GitHub.pages_https_required_after
  end

  # Force the https_redirect value based on whether it is allowed/required.
  #
  # Returns true.
  def set_https_redirect
    return if repository.nil?

    if https_redirect_required?
      self.https_redirect = true
    elsif !https_available?
      self.https_redirect = false
    end

    true
  end

  # For the hsts_max_age value for new users.
  #
  # Returns true
  def set_hsts_max_age
    self.hsts_max_age = if hsts_required?
      1.year.to_i
    elsif https_available?
      # Do not force HSTS for all Pages sites since we might not have certs for them.
      # This change allows us to enable HSTS on the console for specific sites.
      # If they have are HTTPS-able, then let us set an HSTS value.
      hsts_max_age
    else
      nil
    end

    true
  end

  # The certificate associated with this Page's CNAME.
  #
  # Returns a Promise which resolves to an Page::Certificate instance or nil.
  def async_certificate
    return @async_certificate if defined?(@async_certificate)

    @async_certificate = async_certificate_domain.then do |host|
      next nil unless host
      Platform::Loaders::PageCertificateByDomain.load(host)
    end
  end

  # The certificate associated with this Page's CNAME.
  #
  # Returns a Page::Certificate instance or nil.
  def certificate
    @certificate ||= async_certificate.sync
  end

  # The domain the certificate should be issued for.
  #
  # Returns a Promise which resolves to a string hostname or nil if no custom domain is specified.
  def async_certificate_domain
    return @async_certificate_domain if defined?(@async_certificate_domain)

    @async_certificate_domain = url.async_custom_domain?.then do |has_custom_domain|
      next nil unless has_custom_domain
      url.async_host
    end
  end

  # The domain the certificate should be issued for.
  #
  # Returns a string hostname or nil if no custom domain is specified.
  def certificate_domain
    return @certificate_domain if defined?(@certificate_domain)
    @certificate_domain = async_certificate_domain.sync
  end

  def set_subdomain_on_create
    if GitHub.multi_tenant_enterprise?
      set_subdomain_to_match_nwo
    else
      set_subdomain_to_match_visibility
    end
  end

  # Proxima page subdomains are named after their repositories and owners
  def set_subdomain_to_match_nwo
    return nil unless GitHub.multi_tenant_enterprise?
    return nil if primary?
    return nil if repository.nil?

    begin
      update_attribute :subdomain, Subdomain.new(repository: repository).value
    rescue ActiveRecord::RecordNotUnique
      # In Proxima it is possible to have two repo names generate the same subdomain
      update_attribute :subdomain, Subdomain.new(repository: repository).value(make_unique: true)
    end
  end

  # Regular private page subdomains have random names
  # Writes a new subdomain which only has a normalized repo name
  # that only allows a-z (no uppercase), 0-9, and a hyphen (-)
  # If we detect that an org has two repos that conflict (e.g. they have both repo_a and repo-a),
  # we'll have to store one with a random number at the end.
  # Returns the value written to the database or `nil` if an existing subdomain was removed
  # If new routing experience enabled, writes a new subdomain in format adj-noun-routing_id_in_hash
  def set_subdomain_to_match_visibility
    return nil if GitHub.multi_tenant_enterprise?
    return nil if primary?
    return nil if repository.nil?
    return nil unless repository.plan_supports_private_pages?

    return update_attribute :subdomain, nil if public?

    # If the subdomain is already set, don't overwrite it to support legacy subdomains.
    return subdomain if subdomain.present?

    begin
      update_attribute :subdomain, Subdomain.new(repository: repository).value
    rescue ActiveRecord::RecordNotUnique
      # In Proxima it is possible to have two repo names generate the same subdomain
      update_attribute :subdomain, Subdomain.new(repository: repository).value(make_unique: true)
    end
  end

  def set_custom_subdomain(display_value)
    database_value = "#{display_value}_#{shortcode}"
    update_attribute :custom_subdomain, database_value if CustomSubdomain.new(database_value, shortcode).validate
  end

  # In Proxima, subdomain stores the default subdomain value and custom_subdomain should override it if available.
  # Both custom_subdomain and subdomain includes the tenant shortcode in the database to maintain uniqueness.
  # If a custom subdomain exists, it should be used for routing rather than the subdomain
  def async_display_routed_subdomain_proxima
    async_owner.then do |owner|
      next unless owner
      self.custom_subdomain.nil? ? self.subdomain&.chomp("_#{shortcode}") : self.custom_subdomain&.chomp("_#{shortcode}")
    end
  end

  # Use for Proxima support to select the display value of custom subdomain if it exist and of subdomain if it does not.
  def display_routed_subdomain_proxima
    # Async for graphql api support
    async_display_routed_subdomain_proxima.sync
  end

  # Similar to display_login vs login in User table. Should be used in Proxima for anything user facing.
  def async_display_custom_subdomain
    async_owner.then do |owner|
      next unless owner
      self.custom_subdomain&.chomp("_#{shortcode}")
    end
  end

  def display_custom_subdomain
    # Async for graphql api support
    async_display_custom_subdomain.sync
  end

  # Similar to display_login vs login in User table. Shouild be used in Proxima for anything user facing.
  def display_subdomain
    GitHub.multi_tenant_enterprise? ? self.subdomain&.chomp("_#{shortcode}") : self.subdomain
  end

  # In Proxima, a repo will be owned by either an org or an emu user. Backup to CurrentTenant if they are not.
  # Shortcodes are guaranteed to be globally unique, but at time of writing not all calls will have a CurrentTenant.
  # When all calls are guaranteed to have a CurrentTenant, we can replace this method with calls to CurrentTenant.
  def shortcode
    return nil unless GitHub.multi_tenant_enterprise?
    if owner.business
      owner.business.shortcode
    elsif owner.is_enterprise_managed?
      owner.enterprise_managed_business.shortcode
    else
      GitHub::CurrentTenant.get.shortcode
    end
  end

  # A page URL, represented as a distinct class.
  #
  # Returns a Page::URL instance for the current Page.
  def url
    @url ||= Page::URL.new(self)
  end

  # Surrogate key used purge pages Fastly cache.
  # The format based on https://github.com/github/pages/blob/2caaa4472df9356f8bb24f078b722b1828de2a3f/lib/pages_jekyll/purger.rb#L62
  #
  # Returns Pages Fastly purge key.
  def fastly_purge_key
    url.host.tr(".", "_").downcase
  end

  # Enqueue a page-build job for this page.
  #
  # Returns nothing.
  def publish(pusher = nil, git_ref_name: nil)
    return unless GitHub.pages_enabled?
    return if owner&.spammy
    return unless repository&.plan_supports_pages?
    return if owner&.has_any_trade_restrictions? && repository&.private?
    return if workflow_build_enabled?

    # disable automatic publishing on non-source branch if in `:pages_preview_deployments` feature
    return if GitHub.flipper[:pages_preview_deployments].enabled?(repository) && git_ref_name.present? && (source_branch != git_ref_name)

    GitHub.dogstats.increment "pages.build_jobs"

    # This build is initiated by a staff user that would otherwise not have push access
    if GitHub.guard_audit_log_staff_actor? && pusher.site_admin? && !repository.pushable_by?(pusher)
      actor_hash = GitHub.guarded_audit_log_staff_actor_entry(pusher)
      pusher = repository.gh_pages_rebuilder(User.staff_user)
      repository.instrument :pages_build, actor_hash
    end

    disabled_reason = dynamic_workflow_disabled_reason
    if disabled_reason
      if nojekyll? && (GitHub.flipper[:pages_static_only_deployment].enabled?(repository) || GitHub.flipper[:pages_static_only_deployment].enabled?(owner))
        pages_build_version = repository.heads.find(source_branch)&.target.oid
        repo_archive_tar_endpoint = "#{GitHub.api_url}/repos/#{repository.name_with_owner_for_api}/tarball/#{source_branch}"

        # Create a Pages Deployment record
        create_or_find_deployment_for(source_branch)

        # Create a GithHub deployment record
        github_deployment = create_or_find_github_deployment

        payload = {
          path: GitHub::Routing.dpages_storage_path(self.id, revision: pages_build_version),
          artifact_url: repo_archive_tar_endpoint, # artifact_url will be used to send the repository tarball url
          environment: environment,
          pages_build_version: pages_build_version,
          global_id: repository.next_global_id,
          owner_id: repository. owner.id,
          repo_id: repository.id,
          writing_non_voting: false,
          ref: source_branch,
          preview: false,
          deployment_type: 1, # 1 for static only deployment, This is an Enum on the Pages-deployer side represented as STATIC_DEPLOYMENT https://github.com/github/pages-deployer/blob/b482872e0e7bc221eac6718621daa18a4e614112/internal/model/deployment_info.go#L47-L49
          sub_dir: source_subdir,
          nwo: repository.name_with_display_owner,
          github_deployment_id: github_deployment.id,
        }

        # sending to review-lab environment if the repo within paper-spa organization on dotcom
        queue_name = (repository.owner.name == "paper-spa" && !GitHub.enterprise?) ? "pages-deployer-review-lab" : "pages-deployer"
        GitHub::Pages::PagesDeployerClient.enqueue(payload, queue_name)

        GitHub.dogstats.increment "pages.static_only"
      else
        # dynamic workflows not enabled. Build the job using legacy build system
        if GitHub.enterprise?
          publish_legacy(pusher, git_ref_name)
        else
          GitHub.dogstats.increment "pages.legacy_build.skipped", tags: ["reason:#{disabled_reason}"]
        end
      end
    else
      create_or_find_deployment_for(source_branch)
      begin
        publish_actions(pusher, git_ref_name)
      rescue Actions::AppInstaller::InstallationError => e
        # Don't report the error, just track a metric and fallback to legacy build
        # In the case of a spammy_target error, ignore the metrics and the fallback (we don't build sites for spammy users)
        if e.reason != :spammy_target
          GitHub.dogstats.increment "pages.build_integration_fallback"
          GitHub.dogstats.increment "pages.legacy_build", tags: ["reason:app_installation_error", "installation_error:#{e.reason}"]
          publish_legacy(pusher, git_ref_name) if GitHub.enterprise?
        end
      end
    end
    GlobalInstrumenter.instrument "pages.build", {
      actor: pusher,
      repository_owner: owner,
      page: self,
    }

    true
  end

  # Purge page cdn.
  def purge_cdn
    GitHub.fastly.purge_cdn(fastly_purge_key)
  end

  def page_queue
    self.class.page_queue
  end

  def unpublish
    self.class.transaction do
      raise ActiveRecord::Rollback unless update(built_revision: nil)
      delete_built_site_data
      PageUpdate.create(page_id: self.id, event: :delete_event) if GitHub.multi_tenant_enterprise?
    end
  end

  # The queue to use when building new pages.
  def self.page_queue
    if build_in_docker?
      "pages-docker"
    else
      :page
    end
  end

  def page_build_yaml(checkout_branch)
    # Working directory here will be relative to the directory mounted in the Action's container
    working_directory = ".#{source_dir == "/" ? "" : source_dir }"

    runs_on = if use_only_self_hosted_runners?
      if run_dynamic_workflow_on_mariner2_runner?
        "mariner2"
      else
        "self-hosted"
      end
    else
      "ubuntu-latest"
    end

    # used to talk to telemetry API using curl instead of `gh api`
    # At the moment only because `gh api` isn't setup to hit the multi-tenant endpoint
    use_curl_for_telemetry = true unless should_use_gh_api?

    # Define location of the Pages actions
    build_pages_action = "actions/jekyll-build-pages@#{GitHub.build_pages_action_tag}"
    upload_pages_artifact_action = "actions/upload-pages-artifact@#{GitHub.upload_pages_artifact_action_tag}"
    deploy_pages_action = "actions/deploy-pages@#{GitHub.deploy_pages_action_tag}"
    protected_by_ip_allowlist = repository.protected_by_ip_allowlist?

    template_file = "page_build_action_v2.yaml.erb"

    # Evaluate the YAML template
    template = ERB.new File.read(Rails.root.join("packages", "artifacts", "app", "models", "page", "template", template_file))
    template.result(binding)
  end

  def self.build_in_docker?
    !GitHub.enterprise? && (Rails.env.production? || Rails.env.development?)
  end

  def lock_build
    cache_lock_obtain("page:#{id}:lock")
  end

  def unlock_build
    cache_lock_release("page:#{id}:lock")
  end

  def lock_build_for_pusher(pusher)
    cache_lock_obtain("page:pusher:#{pusher.id}:lock")
  end

  def unlock_build_for_pusher(pusher)
    cache_lock_release("page:pusher:#{pusher.id}:lock")
  end

  # Public: Get an auth token for the user and session.
  #
  # session - the UserSession instance to which the token should be tied.
  #
  # Returns the String token.
  def auth_token(session:)
    @token ||= GitHub::Authentication::SignedAuthToken.generate(
      session: session,
      scope: auth_token_scope,
      expires: 24.hours.from_now,
    )
  end

  def auth_token_scope
    "PrivatePages:#{repository.id}"
  end

  # The new shiny delete_pages for the dpages world
  def delete_built_site_data
    self.class.transaction do
      update_attribute :built_revision, nil

      destroy_dependent_pages_replicas
    end
  end

  # Clear the cname, regardless of whether there is a valid CNAME blob.
  # Used when a domain has been claimed by a user who does not own it.
  def clear_cname
    update_attribute :cname, nil
  end

  # Clear the cname and parent domain, regardless of whether there is a valid CNAME blob.
  # Used by the delete protected domain job to disassociate pages.
  def disassociate_domains
    update_attribute :cname, nil
    update_attribute :parent_domain, nil
  end

  # Commit new CNAME blob to the head of the pages branch and trigger rebuild
  # Removes CNAME file if input is blank.
  #
  # Returns new cname or "" on success, nil if no change
  def write_cname(cname, committer)
    # Get old and new cnames
    old_cname = cname_from_blob
    new_cname = normalize_cname(cname)

    # Skip conditions: no repository or no changes
    return nil if repository.nil? || (pages_ref.nil? && build_type != "workflow")
    return nil if new_cname == old_cname && new_cname == self.cname
    return nil if self.deleted_at && should_soft_delete?

    # Validate new cname
    Page::CName.new(self, new_cname).validate if new_cname.present?

    # If an actual change needs to be commited and not ignore blob cname, make a commit
    if new_cname != old_cname && !ignore_blob_cname?
      op = if !cname_exists?
        "Create"
      elsif new_cname.present?
        "Update"
      else
        "Delete"
      end
      repository.heads.read(repository.pages_branch).append_commit(
        { message: "#{op} CNAME", author: committer },
        committer,
        sign: true,
      ) do |files|
        if op == "Delete"
          files.remove(cname_path)
        else
          files.add(cname_path, new_cname)
        end
      end

      # Call rebuild here without queuing an actual build. This ensure the model is saved
      # and the HTTPS propagation jobs is queued too.
      #
      # Note: the actual build will be queued up in the background via the push that was just done above.
      # Since the push event cannot be cancelled easily, we cancel what we control here.
      repository.rebuild_pages(committer, skip_build: true)

    # In other cases (cname actually matches the CNAME file but not the db attribute),
    # so fix the db attribute
    elsif new_cname != self.cname
      update_attribute :cname, new_cname
    end

    # Publish cname_change event to Hydro
    GlobalInstrumenter.instrument "pages.cname_change", {
      cname: new_cname,
      old_cname: old_cname,
      actor: committer,
      page: self,
    }

    # Return the new cname (or an empty string if the cname was deleted)
    new_cname || ""
  end

  # instrumented DNS healthcheck for the cname - may block for up to 2s
  def cname_health_check(cname)
    check = GitHubPages::HealthCheck::Site.new(cname)
    return nil if !check.present?
    alt_domain = get_alt_domain(cname)
    return { "domain": check } if alt_domain.empty?
    alt_domain_check = GitHubPages::HealthCheck::Site.new(alt_domain)

    { "domain": check, "alt_domain": alt_domain_check }
  end

  # When create a new GitHub pages, check repository visibility and enforce to pages.
  def set_visibility
    return self.public = false if GitHub.multi_tenant_enterprise? # Pages are always private on Proxima
    return self.public = true unless GitHub.private_pages_enabled?

    return if repository.nil?

    # To be created with private visibility, both the repo owner and the repo's parent
    # owner (if it's a fork) must both have plans that support private pages.
    supports_private_pages = repository.can_have_private_pages?
    if GitHub.flipper[:pages_forked_visibility_fix].enabled?(repository) || GitHub.flipper[:pages_forked_visibility_fix].enabled?(repository.owner)
      if repository.fork?
        supports_private_pages = supports_private_pages && repository.owner.plan_supports?(:private_pages)
      else
        supports_private_pages = repository.owner.plan_supports?(:private_pages)
      end
    end

    if supports_private_pages
      return self.public = true if repository.is_user_pages_repo? || repository.org_members_can_only_create_public_pages?
      return self.public = false if repository.org_members_can_only_create_private_pages? && !repository.public?
      self.public = repository.public? if repository.org_members_can_create_both_pages?
    end
  end

  # Determine if this is a nojekyll page
  #
  # Returns true if the source dir contains a .nojekyll file.
  def nojekyll?
    repository.includes_file?(source_file_path(".nojekyll"), repository.pages_branch)
  end

  def dynamic_workflow_disabled_reason
    # Actions is enabled (false in enterprise for instance, this check is also needed for tests not to be flacky)
    return :actions_disabled unless GitHub.actions_enabled?
    # GHEC only
    return :github_enterprise if GitHub.enterprise?
    # GH apps are available
    return :github_apps_unavailable if GitHub.pages_github_app.nil? || GitHub.launch_github_app.nil?
    # Repository is nil
    return :repository_nil unless repository
    # Plan support Actions (this will exclude legacy plans for instance)
    # If the repo is public we allow it since actions is supported for public repos
    return :plan_does_not_support_actions unless repository.owner.plan.actions_eligible? || repository.public?
    # The repository allows all actions
    return :repo_disallows_all_actions if repository.actions_disabled_at_any_level?
    # The repository allows GitHub owned actions
    # TODO: We need to revisit that later and make sure to also support the "Allow select actions" option (more fine-grained control)
    return :repo_disallows_github_actions if repository.most_restrictive_allowlist && !repository.allows_github_owned_actions?
    return :business_uses_only_self_hosted_runners if use_only_self_hosted_runners? && !run_dynamic_workflow_on_self_hosted_runner? && !run_dynamic_workflow_on_mariner2_runner?
    # Actions has not been blocked for the repository or the user
    # TODO: When Pages takes an official dependency on Actions, we need to revist this stance
    return :action_invocation_blocked if repository.action_invocation_blocked?

    # It requires pages existed due to "/repositories/:repository_id/pages/deployment" API
    return :page_id_nil if self.id.nil?
    return :source_branch_nil if source_branch.nil?

    nil
  end

  # Whether building with GitHub Actions dynamic workflow is enabled for this repository
  def dynamic_workflow_enabled?
    !dynamic_workflow_disabled_reason
  end

  # If a preview deployment exists for the given ref_name on this repository.
  #
  # git_ref_name - a String ref name to search for, e.g. "branch-build" (omit "refs/heads")
  #
  # Returns true if any Page::Deployment exists for the given git_ref_name
  def deployment_enabled_for?(git_ref_name)
    deployments_for(git_ref_name).exists?
  end

  # The ActiveRecord::Association for the Page::Deployment association with the given git_ref_name
  #
  # git_ref_name - a String ref name to search for, e.g. "branch-build" (omit "refs/heads")
  #
  # Returns the ActiveRecord::Association
  def deployments_for(git_ref_name)
    deployments.where(ref_name: git_ref_name)
  end

  # The Page::Deployment or the given git_ref_name
  #
  # git_ref_name - a String ref name to search for, e.g. "branch-build" (omit "refs/heads")
  #
  # Returns the Page::Deployment instance for the given git_ref_name or nil if none exists
  def deployment_for(git_ref_name)
    deployments_for(git_ref_name).first
  end

  def primary_deployment
    return nil unless built_revision.present?
    deployments.where(revision: built_revision).first
  end

  def workflow_run
    return nil unless primary_deployment&.check_run_id.present?
    Actions::WorkflowRun.find_by_id(primary_deployment.check_run_id)
  end

  # Create or find the deployment for a specific ref_name
  # The revision will be null for new deployments
  # ONLY lib/github/pages/builder.rb should modify revisions on deployments
  def create_or_find_deployment_for(ref_name)
    preexisting = deployments_for(ref_name).first
    return preexisting if preexisting.present?

    begin
      Page::Deployment.create!(page_id: self.id, ref_name: ref_name)
    rescue ActiveRecord::RecordNotUnique => e
      # This happens when the deployment.token clashes with another deployment token
      # for the same page_id. The token must be unique based on the page_id.
      # In a best-effort, we'll give this another try.
      Page::Deployment.create!(page_id: self.id, ref_name: ref_name)
    end
  end

  # Create or find an GitHub deployment for the Page
  def create_or_find_github_deployment
    preexisting = repository.deployments.by_sha(pages_ref.commit.oid)
    return preexisting.first if preexisting.present?

    options = {
      sha: pages_ref.commit.oid,
      creator: GitHub.pages_github_app.bot,
      repository: repository,
      environment: environment,
      ref: source_branch
    }

    ::Deployment.create!(options)
  end

  # Find the Page's Page::Deployment for its source branch.
  #
  # Returns a Promise which resolves to a Page::Deployment or nil.
  def async_primary_deployment
    Platform::Loaders::PageDeploymentByRefName.load(id, source_branch)
  end

  # Create a Page cname certificate
  #
  # Returns true if the certificate was created, false otherwise.
  def create_cname_certificate
    create_certificate(cname)
  end

  def create_certificate_in_background
    PageCertificateCreateJob.perform_later(self)
  end

  # List pages latest artifacts with passed limit
  #
  # Returns artifact list
  def latest_artifacts(limit: 1)
    artifact_ids = Artifact.connection.select_values(Arel.sql(<<-SQL, repo_id: repository.id, artifact_name: ARTIFACT_NAME, limit: Arel.sql(limit.to_s)))
      SELECT artifacts.id
      FROM artifacts
      INNER JOIN check_suites ON check_suites.id = artifacts.check_suite_id
      WHERE check_suites.repository_id = :repo_id AND
      artifacts.repository_id = :repo_id AND
      artifacts.name = :artifact_name
      order by artifacts.id desc
      limit :limit
    SQL
    artifacts = Artifact.where(id: artifact_ids, repository_id: repository.id).order(id: :desc)
  end

  # Finds an artifact by ID, but only if it belongs to the page through a check suite
  def get_artifact(id)
    Artifact.joins("INNER JOIN check_suites ON check_suites.id = artifacts.check_suite_id")
      .where(check_suites: { repository_id: repository.id })
      .where(id: id, repository_id: repository.id)
      .where(name: ARTIFACT_NAME)
      .first
  end

  # Get the latest artifact
  #
  # Returns latest artifact
  def latest_artifact
    latest_artifacts&.first
  end

  # Create a Page::Certificate for this page.
  #
  # Returns true if the certificate was created, false otherwise.
  def create_certificate(domain_name)
    return false unless eligible_for_certificate?

    # Certificate for domain name already exists.
    reload # clear the caching of any previously nil `@certificate` value

    # Swap the primary and the alternate domain on the certificate
    #
    # If certificate has already been issued for a domain and user comes back and
    # changes the cname to www variant of the already created certificate, we end
    # up in a situation where we have two records in the Page::Certificate
    #
    # If a certificate exists for the alternate domain and the primary domain
    #       * delete the alt_domain certificate
    #       * retrigger the certificate provisioning flow
    # If a certificate exists but only for the alternate domain
    #       * flip the certificate object
    if cname.present? && GitHub.flipper[:pages_domain_duplication].enabled?(repository.owner)
      alt_domain = get_alt_domain(cname)
      if alt_domain.present?
        alt_domain_certificate = Page::Certificate.find_by_domain(alt_domain)
        if alt_domain_certificate.present?
          GitHub.logger.info("alt_domain_certificate_exists: alt_domain certificate exists", {
                    "gh.pages.domain" => cname,
                    "gh.pages.alternate.domain" => alt_domain,
                    "gh.pages.id" => self.id
                    })

          if certificate.present?
            GitHub.logger.info("alt_domain_certificate_exists: initiate cleanup on alternate certificate", {
                              "gh.pages.alternate.domain" => alt_domain,
                              "gh.pages.id" => self.id
                              })
            alt_domain_certificate.destroy_certificate
            certificate.resume_flow unless certificate.usable?
          else
            GitHub.logger.info("alt_domain_certificate_exists: initiate flip", {
                                "gh.pages.alternate.domain" => alt_domain,
                                "gh.pages.id" => self.id
                               })
            alt_domain_certificate.flip_certificate
            alt_domain_certificate.reload
          end
          return false
        end
      end
    end

    return false if certificate.present?

    cert = begin
            Page::Certificate.create(domain: domain_name)
          rescue ActiveRecord::RecordNotUnique => e
            Failbot.report(e, app: "pages-certificates")
            return
          end

    !cert.new_record?
  end

  def eligible_for_certificate?

    # Our Let's Encrypt integration isn't enabled.
    return false unless GitHub.pages_custom_domain_https_enabled?

    # CNAME is blank and subdomain is blank.
    return false if cname.blank? && subdomain.blank?

    # Ensure the DNS is configured properly.
    return Page::Certificate.eligible?(cname) if cname
    false
  end

  def cname_digest
    return unless cname_exists?
    Digest::SHA256.base64digest(cname)[0, 5]
  end

  def dns_kv_key
    "#{cname_digest}-pages-#{id}-dns-response"
  end

  def job_status_kv_key
    "#{cname_digest}-pages-#{id}-job-status"
  end

  def page_build_tracking_key
    "pages-build-tracking-#{id}"
  end

  def latest_build
    build_id = Pages::KV.store.get(page_build_tracking_key).value!
    Page::Build.find_by_id(build_id)
  end

  def complete_build
    return if id.nil?
    build = latest_build
    return unless build
    build.complete!((Time.now - build.updated_at) * 1_000)
    Pages::KV.store.del(page_build_tracking_key)
  end

  def fail_build
    return if id.nil?
    build = latest_build
    return unless build
    error = StandardError.new("Page build failed.")
    build.error!(error)
    Pages::KV.store.del(page_build_tracking_key)
  end

  def protected_domain_state
    protected_domain&.state
  end

  def domain_unverified_at
    domain = protected_domain
    return unless domain.present? && domain.state == "pending"

    domain.unverified_at
  end

  def display_cname
    return @display_cname if defined?(@display_cname)
    @display_cname = Addressable::IDNA.to_unicode(cname)
  end

  # Soft-delete pages are treated as deleted so we don't route to them
  def soft_delete!
    return false if self.deleted_at
    return false unless should_soft_delete?
    self.update!(deleted_at: DateTime.now.utc, deleted_cname: self.cname, cname: nil)
  end

  def should_soft_delete?
    GitHub.flipper[:pages_soft_deletion].enabled?(repository) || GitHub.flipper[:pages_soft_deletion].enabled?(owner)
  end

  def soft_deleted?
    !!self.deleted_at
  end

  def restore_deleted
    return unless self.persisted?
    return false if self.deleted_at_in_database.nil?
    self.update(deleted_at: nil, cname: self.deleted_cname, deleted_cname: nil)
  rescue ActiveRecord::RecordNotUnique
    # In the case where we can't restore the cname because it's already been taken, try again with no cname.
    # Since we know page is persisted, then the only RecordNotUnique we could get from the
    # original update is the result of `cname` not being unique. Try without cname.
    self.update(deleted_at: nil, cname: nil, deleted_cname: nil)
  end

  def delete_or_restore_to_match_plan!
    return if GitHub.single_or_multi_tenant_enterprise?
    if private? ? repository.plan_supports_private_pages? : repository.plan_supports_pages?
      restore_deleted
    elsif should_soft_delete?
      soft_delete!
    else
      repository.unpublish_page
    end
  end

  def should_restore_deleted_after_changing_visibility?
    saved_change_to_public? && soft_deleted? && public?
  end

  # If the page is soft deleted, we can restore it if the repository is on a plan that supports private pages
  # or if the repository is public and the owner is on a plan that supports private pages
  #
  # Returns true if the page can be restored, false otherwise
  def can_restore_soft_deleted?
    return true if (soft_deleted? &&
                     ((private? && repository.owner.plan_supports_private_pages?) ||
                     (public? && repository.owner.plan_supports?(:pages, visibility: :private))))
    false
  end

  private

  def set_repository_page
    # Some validation logic depends on the repository knowing about the inverse association, so we set it early in the
    # flow. Using GitHub::PrefillAssociations.prefill_associations here to avoid triggering the additional callbacks
    # that would be called when using repository#page=
    GitHub::PrefillAssociations.prefill_associations([repository], :page, available_records: [self])
  end

  def saved_change_to_source_fields?
    saved_change_to_source_ref_name? || saved_change_to_source_subdir? || saved_change_to_source?
  end

  def instrument_source
    # Any updates to this model should populate source_ref_name and source_subdir which comprise `source_field`, so we
    # can expect those to be set. However, for old_source_field, the previous value might only be in the deprecated field,
    # so we need to account for that.
    source_field = "#{source_ref_name} #{source_subdir}"
    old_source_field = "#{source_ref_name_before_last_save} #{source_subdir_before_last_save}"
    old_source_field = source_before_last_save if old_source_field.blank?

    repository.instrument(:pages_source, source: source_field, old_source: old_source_field)

    if source_branch == "main" || source_branch == "master" || source_branch == "gh-pages"
      GitHub.dogstats.increment "pages.source", tags: ["branch:#{source_branch}", "dir:#{source_dir}"]
    else
      GitHub.dogstats.increment "pages.source", tags: ["branch:other", "dir:#{source_dir}"]
    end
  end

  def instrument_cname
    repository.instrument :pages_cname,
      cname: cname,
      old_cname: cname_before_last_save

    if cname.blank? && cname_before_last_save.present?
      GitHub.dogstats.increment "pages.cname", tags: ["action:removed"]
    elsif cname_before_last_save.blank? && cname.present?
      GitHub.dogstats.increment "pages.cnames", tags: ["action:added"]
    elsif cname.present? && cname_before_last_save.present?
      GitHub.dogstats.increment "pages.cnames", tags: ["action:changed"]
    end
  end

  def instrument_https_redirect_toggled
    return unless repository

    if https_redirect?
      GitHub.dogstats.increment "pages.https_redirect", tags: ["action:enabled"]
      repository.instrument :pages_https_redirect_enabled
    else
      GitHub.dogstats.increment "pages.https_redirect", tags: ["action:disabled"]
      repository.instrument :pages_https_redirect_disabled
    end
  end

  def instrument_visibility
    if public?
      GitHub.dogstats.increment "pages.visibility", tags: ["action:public"]
      repository.instrument :pages_public
    else
      GitHub.dogstats.increment "pages.visibility", tags: ["action:private"]
      repository.instrument :pages_private
    end
  end

  def instrument_build_type
    GitHub.dogstats.increment "pages.build_type", tags: ["action:#{build_type}"]
    repository.instrument :pages_build_type, build_type: build_type
  end

  def instrument_deleted_at
    if self.deleted_at
      repository.instrument :pages_soft_delete
      GitHub.dogstats.increment "pages.soft_deletion", tags: ["action:delete"]
    else
      repository.instrument :pages_soft_delete_restore, soft_deleted_at: saved_change_to_deleted_at[0]&.utc
      GitHub.dogstats.increment "pages.soft_deletion", tags: ["action:restore"]
    end
  end

  # Sets the CNAME from a file in the repository.
  #
  # Returns true.
  def set_cname
    cname = if !GitHub.pages_custom_cnames?
      nil
    elsif repository.nil? || pages_ref.nil?
      self.cname
    else
      cname_from_blob
    end

    if cname.nil? || cname_error(cname)
      self.cname = nil
      self.parent_domain = nil
      self.www_parent_domain = nil
    else
      self.cname = cname
      self.parent_domain = Page::ProtectedDomain.parent_domain_of(cname)
      if self.cname.downcase.start_with?("www.")
        self.www_parent_domain = Page::ProtectedDomain.parent_domain_of(self.parent_domain)
      else
        self.www_parent_domain = nil
      end
    end

    true
  end

  # Sets the four_or_four from a file in the repository.
  #
  # Returns true.
  def set_404
    return if repository.nil? || pages_ref.nil?

    begin
      self.four_oh_four = !!(repository.blob(pages_ref.commit.oid, "404.html"))
    rescue GitRPC::InvalidObject
      # 404.html is a Git tree, not a blob. Ignore.
      self.four_oh_four = false
    end

    true
  end

  # Lookup the ref for the master or gh-pages branch depending on repo-name
  # not memoized - rely on repo refs collection being cached
  #
  # Returns Ref or nil
  def pages_ref(ref_name = nil)
    repository.refs.find(ref_name || repository.pages_branch)
  end
  public :pages_ref

  def tree_name
    repository.pages_branch
  end
  public :tree_name

  # Read index.html from the root of the pages branch
  #
  # Returns a String or nil if the files doesn't exist
  def index_html
    if pages_ref && (blob = repository.blob(pages_ref.commit.oid, source_file_path("index.html")))
      blob.data
    end
  rescue GitRPC::InvalidObject
    nil
  end
  public :index_html

  # Does repository have a CNAME blob?
  # This method is also used in cname_digest method
  # Returns boolean.
  def cname_exists?
    return cname.present? if ignore_blob_cname?
    return true if pages_ref && repository.blob(pages_ref.commit.oid, cname_path)
    false
  rescue GitRPC::InvalidObject
    false
  end
  public :cname_exists?

  # CNAME from blob, if one exists.
  #
  # Returns a String or nil.
  def cname_from_blob
    return self.cname if ignore_blob_cname?
    if pages_ref && (blob = repository.blob(pages_ref.commit.oid,  cname_path))
      normalize_cname(blob.data)
    end
  rescue GitRPC::InvalidObject
    nil
  end
  public :cname_from_blob

  # path of the CNAME file without a leading slash
  #
  # Returns a String
  def cname_path
    source_file_path("CNAME")
  end
  public :cname_path

  # Repository path of a file in the source dir without leading or trailing slash
  #
  # file = file path inside source-dir, defaults to blank = root
  #
  # Returns a String
  def source_file_path(file = "")
    File.join(source_dir, file).gsub(%r(\A/|/\Z), "")
  end
  public :source_file_path

  # Read a source file, if one exists.
  #
  # file_path is the path inside the source directory
  #
  # Returns blob.data (usually a String) or nil
  def source_file(file_path)
    return if pages_ref.nil?
    blob = repository.blob(pages_ref.commit.oid, source_file_path(file_path))
    blob.data unless blob.nil?
  rescue GitRPC::InvalidObject
    nil
  end
  public :source_file

  # Fetch the source directory
  #
  # Returns a Directory or nil if no pages-branch or no source dir
  def source_directory
    ref = repository.heads.read(source_branch)
    dir = source_file_path
    return nil if !ref.exist? || !repository.includes_directory?(dir, source_branch)
    repository.directory(ref.target_oid, dir)
  end
  public :source_directory

  # Normalizes a user-supplied cname
  #
  # Ignores everything after the first line, trims whitespace, downcases
  # Abstracted from cname_from_blob to make testing easier
  #
  # Returns the cname string, or nil if blank
  def normalize_cname(cname = "")
    unless cname.blank?
      cname = cname.split("\n").first.to_s.downcase.sub(/https?:\/\//, "").strip
      cname = GitHub::Encoding.strip_bom(cname)
      cname = Addressable::IDNA.to_ascii(cname)
    end

    cname unless cname.blank?
  end

  # Validate our CNAME from disk during the build process.
  # Can be called when self.cname is nil - always checks against the
  # content of the CNAME blob.
  #
  # Returns the cname error message string or nil if no error
  def cname_error(cname = cname_from_blob)
    nil if Page::CName.new(self, normalize_cname(cname)).validate
  rescue InvalidCNAME => e
    e.message
  end
  public :cname_error

  # Instrument Page creation.
  def track_page_creation
    repository.instrument :pages_create, cname: cname, source: "#{source_ref_name} #{source_subdir}"
    # Publish visibility change event to Hydro after create page.
    GlobalInstrumenter.instrument "pages.visibility_change", {
      actor: repository.owner,
      page: self,
      public: self.public
    }
    GitHub.dogstats.increment "pages.sites"
    instrument_source if saved_change_to_source_fields?

    GitHub.instrument "page", { action: "created", page_id: self.id }
  end

  # we need to generate the payload before the page is deleted, so we don't lose the data
  sig { void }
  def generate_webhook_payload_for_deletion
    return unless GitHub.elm_internal_webhooks_enabled?

    event_for_delete = Hook::Event::PageEvent.new(
      action: "deleted",
      page_id: id,
      repository_id: repository.id,
      triggered_at: Time.now.utc
    )
    @delivery_system_for_delete = Hook::DeliverySystem.new(event_for_delete)
    @delivery_system_for_delete.generate_hookshot_payloads
  end

  def instrument_destroy
    repository.instrument :pages_destroy, cname: cname, source: "#{source_ref_name} #{source_subdir}", soft_deleted_at: deleted_at&.utc
    GitHub.dogstats.decrement "pages.sites"

    if GitHub.elm_internal_webhooks_enabled?
      unless defined?(@delivery_system_for_delete)
        raise "`generate_webhook_payload_for_deletion` must be called before `instrument_destroy`"
      end

      # Send webhook for deletion event
      @delivery_system_for_delete&.deliver_later
    end
  end

  def instrument_update
    return unless GitHub.elm_internal_webhooks_enabled?

    GitHub.instrument "page", { action: "updated", page: self, changes: previous_changes }
  end

  def destroy_dependent_pages_replicas
    self.class.connection.delete(Arel.sql(<<-SQL, page_id: self.id))
      DELETE FROM pages_replicas WHERE page_id = :page_id
    SQL
  end

  def get_alt_domain(cname)
    # Check if the domain is an apex domain(ex. "example.com")
    return "www.#{cname}" if GitHubPages::HealthCheck::Domain.new(cname).apex_domain?

    # Check if domain starts with www since www subdomains will have an alternate domain. Custom subdomains will not have an alternative domain
    alt_domain = cname.delete_prefix("www.")
    return alt_domain if cname.downcase.start_with?("www.") && GitHubPages::HealthCheck::Domain.new(alt_domain).apex_domain?
    ""
  end

  # Return the protected domain (if any) that is currently covering the domain.
  def protected_domain
    # Don't even do any lookup for invalid cname
    return if self.cname.nil? || cname_error(self.cname)

    # Test the direct domain first (returns it if it is verified)
    direct_domain = Page::ProtectedDomain.find_by(name: self.cname, owner: owner)
    if direct_domain.present? && direct_domain.state == "verified"
      return direct_domain
    end

    # Try the parent domain next (return it if it is verified)
    parent_domain = Page::ProtectedDomain.find_by(name: self.parent_domain, owner: owner)
    if parent_domain.present? && parent_domain.state == "verified"
      return parent_domain
    end

    # If both direct and parent are pending, return the one with the farthest unverified timestamp
    if parent_domain.present? && parent_domain.state == "pending" && direct_domain.present? && direct_domain.state == "pending"
      return parent_domain.unverified_at > direct_domain.unverified_at ? parent_domain : direct_domain
    end

    # Just return anything present
    direct_domain.present? ? direct_domain : parent_domain
  end

  def publish_legacy(pusher, git_ref_name)
    args = [id, pusher&.id]
    args << { "git_ref_name" => git_ref_name } if git_ref_name.present?

    PageBuildJob.set(queue: page_queue).perform_later(*args)
    GitHub.dogstats.increment "pages.dynamic_workflow.disabled"
    GitHub.logger.info("github pages build job queued", {
      "gh.pages.id" => id,
      "gh.actor.id" => pusher&.id,
      "gh.catalog_service" => "github/pages",
    })
  end

  def store_id_for_pages_update
    @page_id_for_update = self.id
  end

  # This is called after the page is destroyed and we add a record to the
  # pages_updates table. We only want to do this if the page was destroyed
  def add_proxima_record_on_delete
    PageUpdate.create(page_id: self.id, event: :delete_event) if destroyed? || deleted_at
  end

  # Any time a page is updated, we add a record to the pages_updates table.
  def add_proxima_record_on_update
    PageUpdate.create(page_id: self.id, event: :update_event)
  end

  def add_proxima_record_on_update_subdomain
    PageUpdate.create(page_id: self.id, event: :update_subdomain_event)
  end

  # Some customers make support requests to reduce their hosted runner concurrency to 0, which prevents
  # GitHub-hosted runners from picking up jobs, and forcing them to use only self hosted runners.
  def use_only_self_hosted_runners?
    # We know that GitHub-hosted runners are disabled at the Business level, rather than at org or repo level
    if repository.owner.business
      hosted_runners = Actions::RunnerGroup
        .for_entity(repository.owner.business, include_hosted_runner_groups: true)
        .find { |group| group.hosted? }
      return true if hosted_runners.nil?
      hosted_runners.size <= 0
    else
      false
    end
  end

  # Used when `gh api` is not working yet for an API endpoint
  # In these situations we can fall back to using other methods like `curl`
  def should_use_gh_api?
    !GitHub.multi_tenant_enterprise?
  end

  def run_dynamic_workflow_on_self_hosted_runner?
    GitHub.flipper[:pages_self_hosted_runner_label].enabled?(repository.owner.business)
  end

  def run_dynamic_workflow_on_mariner2_runner?
    GitHub.flipper[:pages_mariner2_runner_label].enabled?(repository.owner.business)
  end

  def publish_actions(pusher, git_ref_name)
    return if pusher.spammy?
    build = Page::Build.track(repository.page, pusher: pusher, commit: pages_ref.commit.oid)

    ## check to see if there's already a build in progress.
    ## if there is, it means we cancled the build (since we didn't error or succeed, both of which clear the build)
    ## and we need to update the old build before proceeding
    # fail current build if any ongoing build
    fail_build
    Pages::KV.store.set(page_build_tracking_key, "#{build.id}")
    checkout_branch = git_ref_name || source_branch
    workflow_yaml = page_build_yaml(checkout_branch)

    actor = GitHub.pages_github_app.bot
    # If we know the responsible party (and it is a real user), mark them as the actor.
    if pusher&.user?
      actor = pusher
    end

    # Make dynamic workflow API call to launch
    result = repository.run_dynamic_workflow(
      actor: actor,
      workflow: workflow_yaml,
      inputs: nil,
      ref: checkout_branch,
      workflow_name: WORKFLOW_NAME,
      slug: WORKFLOW_NAME,
      integration_name: "pages",
      visibility: :VISIBLE,
      entry_point: :page_publish_actions_run_dynamic_workflow
    )

    # Success
    if result&.call_succeeded?
      GitHub.dogstats.increment "pages.dynamic_workflow.enabled", tags: ["state:success"]

      # For debugging (e.g. via console only)
      true

    # Error
    else
      GitHub.dogstats.increment "pages.dynamic_workflow.enabled", tags: ["state:error"]
      message = result && result.options.has_key?(:message) ? result.options[:message] : "unknown error"
      Failbot.report(RunDynamicWorkflowError.new("Invalid response from run_dynamic_workflow: #{message}"))

      # For debugging (e.g. via console only)
      false
    end
  end

  # Are we adding or removing a deleted_at date?
  def staged_change_to_deleted_at?
    changes["deleted_at"] && changes["deleted_at"].any?(&:nil?)
  end

  def should_emit_page_update_record_on_update?
    return false unless GitHub.multi_tenant_enterprise?
    saved_change_to_public? || (saved_change_to_deleted_at? && deleted_at.nil?)
  end

  def should_emit_page_update_record_on_update_subdomain?
    return false unless GitHub.multi_tenant_enterprise?
    saved_change_to_subdomain? || saved_change_to_custom_subdomain?
  end

  def should_emit_page_deletion_record_on_update?
    return false unless GitHub.multi_tenant_enterprise?
    saved_change_to_deleted_at? && deleted_at.present?
  end

  def ensure_soft_deleted_page_has_no_cname
    return unless should_soft_delete?

    if self.deleted_at && self.cname
      errors.add("cname", "can not be present while the page has a deleted_at date")
    end
  end

  def ensure_live_page_has_no_deleted_cname
    return unless should_soft_delete?

    if self.deleted_at.nil? && self.deleted_cname
      errors.add("deleted_cname", "can not be present unless the page has a deleted_at date")
    end
  end
end
