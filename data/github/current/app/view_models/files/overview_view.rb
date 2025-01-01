# typed: true
# frozen_string_literal: true

module Files
  # Controls the overview page for a repository.
  # eg https://github.com/mozilla/rust
  class OverviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include HydroHelper
    include TextHelper
    include DeploymentsHelper
    include Registry::QueryHelper
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    NUMBER_OF_BLOCKED_CONTRIBUTORS_TO_SHOW = 5

    attr_reader :user, :repository, :page_title,
                :source_url, :location, :cap_view_filter

    # Can the person currently logged in edit this repo's metadata?
    def can_edit_metadata?
      return @can_edit_metadata if defined?(@can_edit_metadata)
      @can_edit_metadata = begin
        return false if repository.locked_on_migration?
        return false if repository.archived?
        batched_authzd_permissions(user, :edit_repo_metadata)
      end
    end

    def show_used_by_sidebar?
      repository.used_by_enabled? unless GitHub.enterprise?
    end

    # Generate an HTML formatted repository description. Also adds a link to
    # jump to the README if applicable.
    #
    # Returns the HTML description.
    def formatted_description
      @formatted_description ||= formatted_repo_description(repository)
    end

    # Should we show the description?
    def show_description?
      !repository.description.blank?
    end

    # Returns Topic records applied to this repository
    def topics
      return @topics if defined?(@topics)
      @topics = repository.topics
    end

    def any_topics?
      return @any_topics if defined?(@any_topics)
      @any_topics = topics.any?
    end

    # What's the website the user has linked to for this repository?
    #
    # Returns a String of the URL to autolink.
    def website
      repository.homepage.to_s
    end

    # Should we show the website?
    def show_website?
      !website.blank?
    end

    def top_languages
      @top_languages ||= repository.top_languages_summarized
    end

    def show_languages?
      top_languages.any?
    end

    def packages_sidebar_section_enabled?
      # Allow temporarily disabling the package sidebar to avoid GitHub Packages downtime taking down repository
      # pages.
      return false if FeatureFlag.vexi.enabled?(:disable_packages_sidebar_section, repository, default: false)

      return @packages_sidebar_section_enabled if defined?(@packages_sidebar_section_enabled)

      @packages_sidebar_section_enabled = repository.sidebar_section_enabled?(:packages)
    end

    def environments_sidebar_section_enabled?
      return @environments_sidebar_section_enabled if defined?(@environments_sidebar_section_enabled)

      @environments_sidebar_section_enabled = repository.sidebar_section_enabled?(:environments)
    end

    def deployments_sidebar_section_enabled?
      return @environments_sidebar_section_enabled if defined?(@environments_sidebar_section_enabled)

      @environments_sidebar_section_enabled = repository.sidebar_section_enabled?(:deployments)
    end

    def pages_url_sidebar_section_enabled?
      # the first condition handles having the checkbox set to false since we may not want
      # to force the user to use the pages url or user already has set a custom url
      return false if repository.homepage.to_s != repository.page.url.to_s
      return @pages_url_sidebar_section_enabled if defined?(@pages_url_sidebar_section_enabled)

      @pages_url_sidebar_section_enabled = repository.sidebar_section_enabled?(:pages_url)
    end

    def releases_sidebar_section_enabled?
      return @releases_sidebar_section_enabled if defined?(@releases_sidebar_section_enabled)

      @releases_sidebar_section_enabled = repository.sidebar_section_enabled?(:releases)
    end

    def show_environments_sidebar?
      environments_sidebar_section_enabled? &&
      can_see_deployments?
    end

    def show_packages_sidebar?
      return false unless repository
      packages_sidebar_section_enabled? && show_packages? && PackageRegistryHelper.allow_access_to_actor?(repository.owner, current_user)
    end

    # Public: Returns whether the repository **might** have any packages or not.
    # Might return `true` even if the user does not have access to the packages.
    #
    # Returns: Boolean
    def might_have_packages?
      return true unless FeatureFlag.vexi.enabled?(:zero_packages_short_circuit_packages_sidebar, @current_user, default: true) # already shipped; defaulting to true

      GitHub.dogstats.time("overview.might_have_packages") do
        # Normally one would use `Registry::QueryHelper#packages_for_query` for a task like this.
        # However, we want to avoid the overhead `packages_for_query` brings with it and most importantly avoid talking to the metadata service.
        # Unlike `packages_for_query` we do not perform additional visibility checks for certain edge cases.
        # This means it's **not** safe to expose the returned count or packages to the user.
        # Since this method is only used to short circuit the async rendering of the packages list when there are 0 packages we can get away with this.
        #
        # Note that we might end up returing `true` here but then render an empty packages list if the user does not have access to the packages.
        # This means we're still doing more async rendering calls than we need but it's a tradeoff we're willing to make for now.
        search = Search::QueryHelper.new(nil, "RegistryPackages",
          current_user: current_user,
          user_session: user_session,
          highlight: false,
          owner: repository.owner,
          repo_id: repository.id,
          query: nil,
          package_type: nil,
          visibility: nil,
          only_deleted_packages: false,
          excluded_packages: [],
          sort: nil,
          per_page: 1, # We do't care about the counts, just if there are any packages.
          page: 1,
          max_offset: max_offset_default
        )["RegistryPackages"]

        # skip prune_results call from execute as prune_results would result in a call to the metadata service.
        results = search.execute(skip_prune_results: true)
        results.total != 0
      end
    end

    # Public: The cached count of the repository's contributors.
    #
    # Returns: Int
    def contributor_count
      @contributor_count ||= CommitContributions.domain.contributors_count_for_repository(repository)
    end

    # Public: The cached count of sponsorable links for the repository
    #
    # Returns: Int
    def sponsorable_count
      key = "repository:sponsorable:count:#{repository.id}:#{repository.updated_at.to_i}"
      @sponsorable_count ||= GitHub.cache.fetch(key) do
        funding_links = repository.funding_links
        count = funding_links.sponsorable_users_ids.count
        count += 1 if funding_links.sponsorable_org_id
        count
      end
    end

    def latest_release
      return @latest_release if defined?(@latest_release)
      @latest_release = Releases::Public.latest_for_repository(repository, current_user)
    end

    def release_count
      return @release_count if defined?(@release_count)
      @release_count = Releases::Public.published_release_count_for_repository(repository.id)
    end

    def tag_count
      return @tag_count if defined?(@tag_count)
      @tag_count = with_database_error_fallback(fallback: -1) { repository.tags.size }
    end

    def latest_release_published_at
      (latest_release.published? && latest_release.published_at) || latest_release.created_at
    end

    def show_code_of_conduct?
      return @show_code_of_conduct if defined?(@show_code_of_conduct)
      @show_code_of_conduct = repository && code_of_conduct_path
    end

    def code_of_conduct_path
      return @code_of_conduct_path if defined?(@code_of_conduct_path)
      @code_of_conduct_path = repository.preferred_files.fetch(:code_of_conduct)&.permalink(use_oid: false)
    end

    memoize def show_security_policy?
      repository && security_policy_path
    end

    memoize def security_policy_path
      repository.preferred_files.fetch(:security)&.permalink(use_oid: false)
    end

    def blocked_contributors
      return @blocked_contributors if defined?(@blocked_contributors)
      return @blocked_contributors = [] unless user && user.ignored_users.any?
      return @blocked_contributors = [] unless show_blocked_contributors_warning?
      @blocked_contributors = repository.blocked_contributors_for(user)
      return [] if @blocked_contributors.empty?

      GitHub.instrument(
        "user.repo_visit_with_blocked_contributors",
        actor: current_user,
        repository: repository,
      )

      @blocked_contributors
    end

    def show_blocked_contributors_warning?
      return false unless user && repository
      return false unless user.show_blocked_contributors_warning?
      return false if repository.owner == user
      return false if CommitContributions.domain.is_contributor?(repository: repository, user: user)

      true
    end

    def license_path
      @license_path ||= repository.preferred_license.try(:path)
    end

    def show_publish_stack_banner?
      @show_publish_stack_banner ||= show_publish_stack_banner
    end

    def show_publish_action_banner?
      @show_publish_action_banner ||= show_publish_action_banner
    end

    def show_use_action_banner?
      @show_use_action_banner ||= show_use_action_banner
    end

    def stack_banner_heading
      "Publish this stack as a release"
    end

    def stack_banner_info
      if repository.public?
        "Make your stack discoverable in releases and the GitHub Marketplace. People will use it to create new repositories."
      else
        "Make your stack discoverable in releases. People with access will use it to create new repositories."
      end
    end

    def show_publish_stack_banner
      false
    end

    def action_slug
      repository.listed_action&.slug
    end

    def action_link_hydro_attrs
      payload = {
        repository_action_id: repository.listed_action&.id,
        source_url: source_url,
        location: location,
      }

      hydro_click_tracking_attributes("marketplace.action.click", payload)
    end

    memoize def can_view_organization_audit_log_link?
      return false unless (organization = repository.owner) && organization.is_a?(Organization)
      return false unless current_user&.feature_enabled?(:audit_log_deep_linking)

      organization.can_read_org_audit_logs?(current_user)
    end

    private

    def show_publish_action_banner
      return false unless logged_in?
      return false if GitHub.enterprise?
      return false if current_user.dismissed_notice?(UserNotice::PUBLISH_ACTION_FROM_REPO_NOTICE)
      return false unless repository.pushable_by?(current_user)
      return false unless repository.listable_action?
      return false if repository.listed_action

      true
    end

    def show_use_action_banner
      return false if GitHub.enterprise?
      return false unless repository.listed_action
      return false if RepositoryAction.where(repository: repository).pluck(:action_package_listed).first

      true
    end

    def can_see_deployments?
      repository.can_see_deployments?(user)
    end

    def show_packages?
      PackageRegistryHelper.show_packages?
    end

    def batched_authzd_permissions(actor, action)
      @batched_authzd_permissions ||= Hash.new do |hash, user|
        manage_topics, edit_repo_metadata = Promise.all([
          repository.async_can_manage_topics?(user),
          repository.async_can_edit_repo_metadata?(user)
        ]).sync

        hash[user] = {
          manage_topics: manage_topics,
          edit_repo_metadata: edit_repo_metadata
        }
      end

      @batched_authzd_permissions[actor].fetch(action)
    end
  end
end
