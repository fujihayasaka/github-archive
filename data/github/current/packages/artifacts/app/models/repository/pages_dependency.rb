# typed: true
# frozen_string_literal: true

# Holds repository methods related to GitHub Pages
module Repository::PagesDependency
  extend T::Helpers

  requires_ancestor { Repository }

  def unpublish_page
    return unless page

    if T.must(page).destroy
      GitHub.logger.info("[repository_unpublish_page] repository page has been destroyed", {
        "code.namespace" => self.class.to_s,
        "code.function" => "unpublish_page",
        "gh.repo.id" => self.id,
      })
    else
      GitHub.logger.info({
        :exception => T.must(page).errors&.full_messages.to_sentence,
        "code.namespace" => self.class.to_s,
        "code.function" => "unpublish_page",
        "gh.repo.id" => self.id,
      })
    end
  end

  def unsupported_pages?
    !plan_supports_pages? && page&.status == "built"
  end

  def plan_supports_pages?
    GitHub.multi_tenant_enterprise? || repository.plan_supports?(:pages)
  end

  def plan_supports_private_pages?
    GitHub.multi_tenant_enterprise? || repository.plan_supports?(:private_pages)
  end

  # Determine if the repository is a user pages repository. User pages
  # repositories are named as "<user>.github.io", or "<user>.github.com" if
  # "<user>.github.io" doesn't exist.
  #
  # Returns true if the repository is a user pages repository, false otherwise.
  def is_user_pages_repo?
    async_is_user_pages_repo?.sync
  end

  def can_have_private_pages?
    return false unless GitHub.private_pages_enabled?
    # In MT enterprise (proxima), Pages are always private
    return true if GitHub.multi_tenant_enterprise?

    # Private Pages is not allowed under a user profile repo
    # This is a special condition to take care of forked repo's from an organization into a user space
    return false if fork? && page&.repository&.owner&.user?

    # Private page is not allowed under an organization that does not have the feature enabled
    return false if fork? && !organization&.plan_supports?(:private_pages)

    # When forked from a organization that doesnt support private pages, the forked repo mimics the same behavior.
    # Hence the explicitly check
    return true if fork? && organization&.plan_supports?(:private_pages)

    private? &&
    plan_supports_private_pages? &&
    !is_user_pages_repo?
  end

  def can_have_public_pages?
    return true unless is_enterprise_managed?
    false
  end

  def async_is_user_pages_repo?
    return Promise.resolve(false) if GitHub.multi_tenant_enterprise?

    async_owner.then do |owner|
      next false unless owner # can happen during deletion
      next true if name_matches_new_user_pages?

      if name_matches_old_user_pages?
        next async_owner_owns_new_user_pages_repo?.then { |owns| !owns }
      end

      false
    end
  end

  def async_owner_owns_new_user_pages_repo?
    async_owner.then do |owner|
      next false unless owner
      Platform::Loaders::RepositoryByName.load(owner.id, "#{owner}.#{GitHub.pages_host_name_v2}").then do |repo|
        # TODO: Platform::Loader loaders should be able to detect if a record exists, rather than loading the whole thing.
        !!repo
      end
    end
  end

  def show_private_pages_prompt?
    return false if plan_supports_pages? && plan_supports_private_pages?
    return false if repository.is_user_pages_repo?
    return false if repository.can_have_private_pages?
    return false if repository.page&.soft_deleted?
    return false if GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    true
  end

  def owner_owns_new_user_pages_repo?
    async_owner_owns_new_user_pages_repo?.sync
  end

  def name_matches_new_user_pages?
    return false unless owner.present?
    name&.downcase == "#{owner.to_s.downcase}.#{GitHub.pages_host_name_v2}"
  end

  def name_matches_old_user_pages?
    return false unless owner.present?
    name&.downcase == "#{owner.to_s.downcase}.#{GitHub.pages_host_name_v1}"
  end

  # Determine if the repository is a user pages repository with a custom domain
  #
  # Returns true if user pages with page.cname, else false.
  def is_cname_user_pages_repo?
    page&.cname && GitHub.pages_custom_cnames? && is_user_pages_repo?
  end

  # Return the expected branch name of which Pages is built.
  #
  # This function should be able to handle the cases where page is nil (and not defined yet)
  # and it does not necessarily return a branch that exists.
  def pages_branch
    # Use source_branch if it was set already, default branch for a user repo and gh-pages
    # for a project repo.
    if page
      # pages with workflow builds don't have a source branch
      return nil if T.must(page).workflow_build_enabled?
      T.must(page).source_branch
    elsif is_user_pages_repo?
      default_branch
    else
      "gh-pages"
    end
  end

  def has_gh_pages_branch?
    heads.include?("gh-pages")
  end

  # Determine if a valid pages branch exists for this repository.
  #
  # Returns true if the repository has a pages branch, false if not.
  def has_gh_pages?
    return false if !GitHub.enterprise? && name_matches_old_user_pages? && owner_owns_new_user_pages_repo?
    return unless online?  # can't check the heads if it's not online
    heads.include?(pages_branch)
  end

  # Determine if the pages branch was created with the Page Generator.
  #
  # Returns true if the pages branch was generated, false if not.
  def has_generated_page?
    if has_gh_pages?
      ref = heads.find(pages_branch)
      blob(ref.target_oid, "params.json").present?
    else
      false
    end
  end

  # Return the pages host name for the owner of this Repository
  #
  # Depends on the pages host_name feature flag right now
  def pages_host_name
    page_for_url.url.async_pages_host_name.sync
  end

  # The GitHub Pages URL for this repository.
  #
  # Returns the String URL of the pages site, regardless of whether the
  #   repository has a pages branch or not.
  def gh_pages_url
    page_for_url.url.to_s
  end

  def async_gh_pages_url
    async_page.then do |_page|
      # page_for_url uses `page`, or creates a temporary Page instance if one doesn't already exist.
      # It should not be saved to the database if it's a new instance.
      page_for_url.url.async_to_s
    end
  end

  # Create a standard page for this repository and writes it to a newly created
  # gh-pages branch.
  #
  # user            - the User record creating the page.
  # params          - Hash passed to the default page template as locals.
  # allow_overwrite - Whether an existing gh-pages branch can be overwritten
  #
  # Returns nothing.
  def pages_create(user, params, allow_overwrite = false)
    fail "branch already exists" if has_gh_pages? && !allow_overwrite
    GitHub::Pages.create(self, user, params)
  end

  # Rebuilds the repository's pages.
  #
  # Checks if a pages branch exists and the page is valid:
  #   Then, if the Pages integration is installed on this repo:
  #     A PageBuild job is queued.
  #   Otherwise:
  #     An AutomaticAppInstalltion event is triggered.
  # When no pages branch exists and a page object exists:
  #   The page is deleted from disk.
  #
  # pusher - The user that caused the pages to be rebuilt. Defaults to the
  #          owner of the repository. This user receives page build
  #          notifications.
  #
  # force_propagate_https_redirect - Whether to propagate_https_redirect to
  #          all other pages belonging to owner.
  #          Defaults to true when this repo is the user-pages repo, else false.
  #
  # git_ref_name - The ref to build. Does *not* include refs/heads/.
  #          Defaults to nil, and is a named parameter.
  #
  # skip_build - Flag indicating if the build step should be skipped. When specified everything else is performed but the
  #              build is not queued.
  #
  # Returns nothing.
  # Raises StandardError when page CNAME validation fails.
  def rebuild_pages(publisher = self.owner, force_propagate_https_redirect = false, git_ref_name: nil, skip_build: false)
    return false if !plan_supports_pages?
    return false if page&.workflow_build_enabled?
    # If we're trying to create the page for the first time but the
    # publisher isn't allowed to create the page, then don't
    # allow the page to be published. This is a security feature.
    return false if !page && !can_create_page?(publisher)
    return false if page && !page&.deleted_at.nil? && !can_create_page?(publisher) && page&.should_soft_delete?
    cname_user_repo_before = is_cname_user_pages_repo?
    if has_gh_pages?
      page = self.page || self.build_page
      rebuilder = gh_pages_rebuilder(publisher)

      if page.save && rebuilder.present?
        # Queue up a build if it was not explicitly requested to be skipped
        if !skip_build
          if should_install_pages_integration?
            AutomaticAppInstallation.trigger(
              type: :page_build,
              originator: {
                page_id: page.id,
                pusher_id: rebuilder.id,
                git_ref_name: git_ref_name,
              },
              actor: self,
            )
          else
            page.publish(rebuilder, git_ref_name: git_ref_name)
          end
        end
      else
        raise ::Page::PageBuildFailed, "Page failed to build for repo id #{repository.id}"
      end
    elsif page = self.page
      page.destroy
    end

    if force_propagate_https_redirect || cname_user_repo_before != is_cname_user_pages_repo?
      queue_propagate_https_redirect
    end
    # TODO: stop returning true for "/staff/repos/:user/:repo/pages/builds"
    true
  rescue GitHub::Pages::Builder::MissingBuildEnvironment
    # ignore missing build environment errors in dev environments. causes
    # script/setup to fail otherwise.
    raise if !Rails.env.development?
  end

  # Determine if the given user can create pages site for this repository.
  # Due to security concerns, we don't want users with just write access to
  # be able to create pages -- we want them to have admin rights to the
  # repository. This better matches the Pages section in the Settings tab
  # in the UI, which allows users to create a Page for this repo only if an
  # admin on the repo.
  # We also want to allow staff to fire off the initial build.
  #
  # Returns true if either the user is an admin of the repo, or is staff.
  def can_create_page?(user)
    return false unless user

    if FeatureFlag.vexi.enabled_or_raise?(:private_pages_org_toggle, organization) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      unless org_members_can_create_public_pages?
        return false if visibility == Repository::PUBLIC_VISIBILITY || is_user_pages_repo? # user repo always publishes a public page
      end
    end

    adminable_by?(user) || user.site_admin?
  end

  # Is the gh-pages build failing?
  #
  # Returns a boolean
  def gh_pages_error?
    has_gh_pages? && gh_pages_last_build && gh_pages_last_build.error?
  end

  # Was the last gh-pages build a success?
  #
  # Returns a boolean
  def gh_pages_success?
    has_gh_pages? && gh_pages_last_build && gh_pages_last_build.status == "built"
  end

  # The error message for the most recently failed gh-pages build.
  #
  # Returns a simple String if the most recent build failed.
  #   (Markdown -> HTML now in EditRepositories::AdminScreen::PagesStatusView)
  # Returns nil otherwise.
  def gh_pages_error
    return unless gh_pages_error?
    gh_pages_last_build.try(:error)
  end

  # Most recent Pages build.
  #
  # Returns a Page::Build if one exists.
  def gh_pages_last_build
    page&.builds&.first
  end

  # Can this repository's Pages site be rebuilt
  # Used in stafftools and in rename jobs
  #
  # user - a user to check
  #
  # Returns true if the site can be rebuilt, otherwise false
  def gh_pages_rebuildable?(user = nil)
    !gh_pages_rebuilder(user).nil?
  end

  # Attemps to find a valid pusher that can trigger a Pages build
  #
  # user - a user to to check
  #
  # Returns the proper pusher, otherwise nil if not possible
  def gh_pages_rebuilder(user = nil)
    return user if user && !user.organization? && pullable_by?(user) && !GitHub.enterprise?
    return user if user && !user.organization? && pullable_by?(user) && user.user? && GitHub.enterprise?
    return unless page

    # The given user can't pull the repo. Find the last non-staff builder and use them
    last_build = T.must(page).builds.first(100).find do |build|
      next false if GitHub.guard_audit_log_staff_actor? && build.pusher_id == User.staff_user.id
      build.pusher && !build.pusher.organization? && pullable_by?(build.pusher)
    end

    last_build.pusher if last_build
  end

  # Determines if the Pages integration is installed on this repo.
  #
  # Returns true the Pages integration exists and is installed on this repo.
  # Returns false othwerise.
  def pages_integration_installation_exists?
    return false unless GitHub.pages_github_app.present?
    IntegrationInstallation
      .with_repository(self)
      .where(integration_id: GitHub.pages_github_app.id)
      .first
      .present?
  end

  # Determines if the  Pages integration should be installed.
  def should_install_pages_integration?
    FeatureFlag.vexi.enabled_or_raise?(:pages_github_app, T.cast(self, Repository)) && !pages_integration_installation_exists? # rubocop:todo GitHub/AvoidCast, GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def org_members_can_create_pages?(visibility: nil)
    org = async_organization.sync

    # Only check for organizations as Pages creation can only be disabled there.
    return true unless org.present?

    case visibility
    when :public
      return org.members_can_create_public_pages?
    when :private
      return org.members_can_create_private_pages?
    end

    org.members_can_create_pages?
  end

  def org_members_can_create_public_pages?
    org_members_can_create_pages?(visibility: :public)
  end

  def org_members_can_create_private_pages?
    org_members_can_create_pages?(visibility: :private)
  end

  def org_members_can_publish_pages?
    page = Platform::Loaders::PageByRepository.load(self.id).sync
    return true if page.present?

    org_members_can_create_pages?
  end

  def org_members_can_only_create_public_pages?
    org_members_can_create_public_pages? &&
    !org_members_can_create_private_pages?
  end

  def org_members_can_only_create_private_pages?
    !org_members_can_create_public_pages? &&
    org_members_can_create_private_pages?
  end

  def org_members_can_create_both_pages?
    org_members_can_create_public_pages? &&
    org_members_can_create_private_pages?
  end

  # Private: Pages operations like `gh_pages_url` require the Page to exist
  # This method returns the page, if it exists, or initializes a new page
  # for calculating URLs prior to the page existing (e.g., previews)
  def page_for_url
    page || Page.new(repository: self)
  end

  # Queue a job to find all pages repos belonging to the same owner
  # and make sure they have valid https_redirect values.
  #
  # Returns nothing.
  def queue_propagate_https_redirect
    if GitHub.pages_https_redirect_enabled? && owner
      PagesPropagateHttpsRedirectJob.perform_later(T.must(owner).id)
    end
  end

  # Public: is the repository protected by an IP allow list, thus warranting
  # the use of the Pages GitHub app token in dynamic workflows?
  def protected_by_ip_allowlist?
    return false unless self.owner&.organization?

    org = T.cast(self.owner, Organization)
    org.ip_allowlist_enabled? || org.ip_allowlist_enabled_on_business?
  end

  # This hash is keyed by stack names that Scout will detect, having values of
  # names of starter workflows for that stack. We optimistically include some
  # stacks that Scout can't detect yet (like Hugo) in the hopes that if/when it
  # is updated to detect them, we can save ourselves some of the extra logic in
  # the rest of the method below the line:
  # `return @suggested_workflows if @suggested_workflows.present?`
  SUGGESTABLE_STACKS = {
    "Gatsby" => "gatsby",
    "Hugo" => "hugo", # not presently detected by Scout
    "Jekyll" => "jekyll",
    "Next" => "nextjs",
    "Nuxt" => "nuxtjs",
    # FIXME: do we care to add gulp, grunt, webpack, astro?
  }.freeze

  def report_workflow_suggestions(detection_type, suggested_workflows = nil)
    detected_by_tag = "detected-by:#{detection_type}"
    if suggested_workflows.present?
      suggested_workflows.each do |stack|
        GitHub.dogstats.increment(
          "pages.suggested-workflows",
          tags: [detected_by_tag, "stack:#{stack}"]
        )
      end
    else
      GitHub.dogstats.increment(
        "pages.suggested-workflows",
        tags: [detected_by_tag]
      )
    end
  end

  def suggested_pages_workflows
    return @suggested_pages_workflows if defined?(@suggested_pages_workflows)
    workflows = suggested_workflows
    return [] if workflows.nil?
    existed_template_ids = PagesWorkflowTemplate.templates(repository, self.owner).map { |template| template["id"] }
    @suggested_pages_workflows = workflows.map { |template_id| "pages/#{template_id}" } & existed_template_ids
  end

  private

  def suggested_workflows
    return @suggested_workflows if defined?(@suggested_workflows)

    detected = TechProjectStackAnalysis.tech_project_stacks(self).reduce([]) do |acc, project|
      acc + project.stacks
    end
    @suggested_workflows = detected.filter_map do |stack|
      SUGGESTABLE_STACKS[stack.name]
    end

    if @suggested_workflows.present?
      report_workflow_suggestions("scout", @suggested_workflows)
      return @suggested_workflows
    end

    # Manually try to detect a supported static site generator

    top_level = self.root_directory
    if top_level
      top_level_files = top_level.tree_entries.map(&:name)

      # Having ALL of the below files & folders definitely indicate Hugo
      if top_level_files.to_set >= ["archetypes", "config.toml", "content", "data", "layout", "static", "themes"].to_set
        @suggested_workflows = ["hugo"]
        report_workflow_suggestions("manual", @suggested_workflows)
        return @suggested_workflows
      end

      maybe_jekyll = top_level_files.include?("_config.yml") || top_level_files.include?("_config.yaml")

      # _config.{yml,yaml} and Gemfile definitely indicate Jekyll
      if maybe_jekyll && top_level_files.include?("Gemfile")
        @suggested_workflows = []
        @suggested_workflows << "jekyll" unless GitHub.enterprise?
        report_workflow_suggestions("manual", @suggested_workflows)
        return @suggested_workflows
      end

      # presence of book.toml suggests mdbook
      if top_level_files.include?("book.toml")
        @suggested_workflows << "mdbook"
      end

      # Just a comfig.toml suggests a Hugo site
      if top_level_files.include?("config.toml")
        @suggested_workflows << "hugo"
      end

      # Just a _config.{yml,yaml} suggests a Jekyll site using the classic github pages pipeline
      if maybe_jekyll
        @suggested_workflows << "jekyll-gh-pages" unless GitHub.enterprise?
      end

      # Historically we supported Jekyll builds on a repo with zero configuration, so
      # we should interpret a repo containing markdown files as a possible Jekyll site
      # FIXME what other generators convert markdown files at the top level of a repo?
      markdown_extensions = %w{ .md .mkdn .mdwn .mdown .markdown }
      if @suggested_workflows.empty? && top_level_files.any? do |file|
        markdown_extensions.each { |md| File.extname(file) == md }
      end
        @suggested_workflows << "jekyll-gh-pages" unless GitHub.enterprise?
      end
    end

    if @suggested_workflows.present?
      report_workflow_suggestions("manual", @suggested_workflows)
    else
      # Still can't deduce any generators? Just suggest the top most popular ones
      report_workflow_suggestions("undetectable")
      @suggested_workflows = %w[nextjs nuxtjs hugo gatsby]
      @suggested_workflows << "jekyll" unless GitHub.enterprise?
    end

    # Tack on static (just hosting the files as-is) as the final option
    @suggested_workflows << "static"

    @suggested_workflows.uniq!

    @suggested_workflows
  end
end
