# typed: strict
# frozen_string_literal: true

module Repos
  module CodeViewSidebar
    sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
    def self.enabled?(current_user)
      FeatureFlag.vexi.enabled?(:ui_route_code_view, current_user, default: false) || FeatureFlag.vexi.enabled?(:react_data_router_code_view_sidebar, current_user, default: false)
    end

    # Gates the unified `/_sidebar` endpoint that returns every sidebar
    # section in a single response. Independent from `enabled?` so the
    # combined endpoint can be rolled out separately from the React sidebar.
    sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
    def self.combined_payload_enabled?(current_user)
      FeatureFlag.vexi.enabled?(:codeview_sidebar_combined_payload, current_user, default: false)
    end

    class CodeViewSidebar
      include UrlHelpers
      include UrlHelper
      include GitHub::RouteHelpers
      include EscapeHelper
      include LanguageHelper
      include AvatarHelper
      include Registry::QueryHelper
      include FeatureFlagHelper

      DEPENDENTS_LIMIT = 8
      HIDE_USED_BY = 100

      sig { params(view_model: Files::OverviewView, current_user: T.nilable(User), current_repository: Repository, user_session: T.untyped).void }
      def initialize(view_model:, current_user:, current_repository:, user_session: nil)
        @view_model = view_model
        @current_user = current_user
        @current_repository = current_repository
        @user_session = user_session
      end

      sig { returns(AboutPayload) }
      def about_payload
        owner = @current_repository.owner

        AboutPayload.new(
          description: @current_repository.description.presence,
          formattedDescription: @view_model.formatted_description.presence,
          website: safe_uri(@view_model.website.presence),
          topics: @view_model.topics.sort_by(&:name).map { |t| Topic.new(name: t.name) },
          showInsights: @view_model.show_insights?,
          stargazerCount: @current_repository.stargazer_count || 0,
          watcherCount: @current_repository.watchers_count,
          forksCount: @current_repository.forks_count,
          stargazersPath: gh_stargazers_path(@current_repository),
          watchersPath: gh_watchers_path(@current_repository),
          forkNetworkPath: gh_fork_network_path(@current_repository),
          activityPath: @view_model.show_insights? ? activity_index_path(owner, @current_repository) : nil,
          customPropertiesPath: custom_properties_path(owner),
          auditLogPath: audit_log_path(owner),
          reportPath: report_path(owner),
          canEditMetadata: @view_model.can_edit_metadata?,
          ownerLogin: owner&.display_login || "",
          repoName: @current_repository.name,
          isOrg: owner&.organization? || false,
          sections: build_sections_config,
          hasCitation: Repositories::Citation.exists?(@current_repository),
          pagesUrl: pages_url,
          templateRepository: template_repository_info,
      )
      end

      sig { returns(SectionsConfig) }
      def build_sections_config
        deployments_enabled = resilient_flag { @view_model.show_deployments_sidebar? }

        # When deployments are enabled, include environment names so the client
        # can render a meaningful skeleton while the full status loads.
        # Returns [] when enabled but no environments exist (client shows empty state).
        deployment_env_names = if deployments_enabled
          ranked = @current_repository.ranked_active_deployment_environments rescue []
          ranked.first(4).map { |_count, env_name| env_name }
        end

        SectionsConfig.new(
          releases: releases_counts,
          sponsors: resilient_flag { @current_repository.show_sponsor_button? },
          deployments: deployment_env_names || false,
          packages: resilient_flag { @view_model.show_packages_sidebar? },
          usedBy: resilient_flag { @view_model.show_used_by_sidebar? || false },
          contributors: true,
          languages: resilient_flag { @view_model.show_languages? },
          cta: resilient_flag { cta_viewable? },
          suggestedWorkflows: resilient_flag { @current_user.present? }
        )
      end

      sig { params(hint_env_names: T.nilable(T::Array[String])).returns(FullSidebarPayload) }
      def full_sidebar_payload(hint_env_names: nil)
        FullSidebarPayload.new(
          configCallToAction: resilient_section { cta_payload },
          releases: resilient_section { releases_payload },
          sponsors: resilient_section { sponsors_payload },
          deployments: resilient_section { deployments_payload(hint_env_names: hint_env_names) },
          packages: @user_session ? resilient_section { packages_payload } : nil,
          usedBy: resilient_section { used_by_payload },
          contributors: resilient_section { contributors_payload },
          languages: resilient_section { languages_payload },
          suggestedWorkflows: resilient_section { suggested_workflows_payload },
        )
      end

      sig { returns(T.nilable(ReleasesPayload)) }
      def releases_payload
        return nil unless @view_model.releases_sidebar_section_enabled?

        owner = T.must(@current_repository.owner)
        latest = @view_model.latest_release

        latest_release_data = if latest
          name = latest.display_name
          tag = latest.tag_name
          if name.present? && tag.present?
            LatestRelease.new(
              name: name,
              path: release_path(tag, @current_repository),
              publishedAt: latest.date_for_display&.iso8601,
            )
          end
        end

        can_write = @current_repository.pushable_by?(@current_user)

        ReleasesPayload.new(
          latestRelease: latest_release_data,
          releasesPath: releases_path(@current_repository),
          tagsPath: tags_path(owner.display_login, @current_repository),
          canWrite: can_write,
          newReleasePath: can_write ? new_release_path(owner.display_login, @current_repository) : nil,
        )
      end

      sig { returns(T.nilable(SponsorsPayload)) }
      def sponsors_payload
        return nil unless @current_repository.show_sponsor_button?

        funding_links = @current_repository.funding_links
        external_links = funding_links.external_funding_accounts.flat_map do |platform_key, account|
          Array(account).filter_map do |acc|
            data = ApplicationController.helpers.funding_link_data(platform_key, acc)
            next unless data
            FundingLink.new(platform: platform_key.to_s, url: data.url, iconUrl: data.icon_url, label: data.label)
          end
        end

        sponsorable_users = funding_links.sponsorable_users.first(4).map do |user|
          SponsorableUser.new(
            login: user.display_login,
            displayName: user.display_name.presence,
            profilePath: "/#{user.display_login}",
            avatarUrl: avatar_url_for(user, 64),
            isSponsoredByViewer: user.sponsored_by_viewer?(@current_user),
          )
        end

        org = funding_links.sponsorable_org
        if org
          sponsorable_users.unshift(SponsorableUser.new(
            login: org.display_login,
            displayName: org.display_name.presence,
            profilePath: "/#{org.display_login}",
            avatarUrl: avatar_url_for(org, 64),
            isSponsoredByViewer: org.sponsored_by_viewer?(@current_user),
          ))
        end

        owner = T.must(@current_repository.owner)
        SponsorsPayload.new(
          sponsorables: sponsorable_users,
          externalFundingLinks: external_links,
          sponsorsPath: "/sponsors/#{owner.display_login}",
          sponsorsLearnMorePath: "/sponsors",
          sponsorableCount: @view_model.sponsorable_count,
        )
      end

      sig { params(hint_env_names: T.nilable(T::Array[String])).returns(T.nilable(DeploymentsPayload)) }
      def deployments_payload(hint_env_names: nil)
        return nil unless @view_model.show_deployments_sidebar?

        # We always compute total_deployment_count so the frontend gets an
        # accurate sum regardless of which code path is taken.
        ranked = @current_repository.ranked_active_deployment_environments
        total_deployment_count = ranked.sum { |count, _env_name| count } if ranked.any?

        if hint_env_names&.any?
          env_names = hint_env_names
        else
          env_names = ranked.any? ? ranked.map { |_count, env_name| env_name } : []
        end

        environments = if env_names.any?
          # Per-environment lookup using the same FORCE INDEX + ORDER BY
          # pattern proven in repositories_controller#environment_status.
          # N is small (handful of environments) and each query is O(1)
          # via the composite index.
          latest_deployments = env_names.index_with do |env_name|
            @current_repository.deployments
              .select(:id, :latest_environment, :latest_deployment_status_id, :transient_environment, :created_at)
              .from("`deployments` FORCE INDEX (index_deployments_on_repo_id_created_and_latest_environment)")
              .where(latest_environment: env_name)
              .order(created_at: :desc)
              .first
          end

          env_names.map do |env_name|
            deployment = latest_deployments[env_name]
            DeploymentEnvironment.new(
              name: env_name,
              state: deployment&.state || "active",
              createdAt: deployment&.created_at&.iso8601,
              path: deployments_path(@current_repository.owner_display_login, @current_repository) + "/#{ERB::Util.url_encode(env_name)}",
            )
          end
        else
          []
        end

        deploy_to_pages = if environments.empty? && @current_user &&
            FeatureFlag.vexi.enabled?(:pages_deploy_flow, @current_user, default: false) &&
            @current_repository.writable_by?(@current_user) &&
            !@current_user.dismissed_repository_notice?(Repositories::DeployToPages::CardComponent::NOTICE_NAME, repository_id: @current_repository.id)
          stack = ApplicationController.helpers.detect_stack(@current_repository)
          framework = stack[:framework]
          package_manager = stack[:package_manager]
          if framework.present? && package_manager.present?
            DeployToPagesInfo.new(
              framework: framework,
              frameworkLabel: Repositories::DeployToPages::CardComponent::FRAMEWORKS[framework] || "project",
              packageManager: package_manager,
              deployPath: deploy_path(@current_repository.owner_display_login, @current_repository, framework: framework, package_manager: package_manager),
              dismissPath: dismiss_repository_notice_user_path(@current_user),
              noticeName: Repositories::DeployToPages::CardComponent::NOTICE_NAME,
              repositoryId: @current_repository.id,
            )
          end
        end

        DeploymentsPayload.new(
          environments: environments,
          deploymentsPath: gh_deployments_path(@current_repository),
          deployToPages: deploy_to_pages,
          totalDeploymentCount: total_deployment_count,
        )
      end

      MAX_SIDEBAR_PACKAGES = 4

      sig { returns(T.nilable(PackagesPayload)) }
      def packages_payload
        return nil unless @view_model.show_packages_sidebar?

        owner = T.must(@current_repository.owner)
        packages_url = if !GitHub.enterprise? || (GitHub.enterprise? && GitHub.registry_v2_enabled_for_enterprise?)
          packages_two_path(owner.organization? ? "orgs" : "users", owner.display_login, repo_name: @current_repository.name)
        else
          packages_path(owner, @current_repository)
        end

        per_page = 3 * (MAX_SIDEBAR_PACKAGES + 1)

        raw_packages, _, total_unfiltered_count = packages_for_query(
          current_user: @current_user,
          user_session: @user_session,
          owner: owner,
          repo_id: @current_repository.id,
          sort: %w[downloads desc],
          page: 1,
          per_page: per_page,
          fail_fast: true,
          use_cached_versions: true,
        )

        package_count = raw_packages.count < per_page ? raw_packages.count : total_unfiltered_count

        serialized_packages = raw_packages.first(MAX_SIDEBAR_PACKAGES + 1).map do |pkg|
          v2_package = pkg.instance_of?(PackageRegistry::PackageMetadata)
          pkg_path = if v2_package
            url_prefix = pkg.owner.organization? ? "orgs" : "users"
            packages_two_view_path(url_prefix, pkg.owner.display_login, pkg.package_type, pkg.name)
          else
            package_path(*@current_repository.name_with_display_owner.split("/"), pkg)
          end
          pkg_type = if pkg.respond_to?(:is_actions_package?) && pkg.is_actions_package?
            "actions"
          else
            pkg.package_type.to_s
          end

          PackageItem.new(name: pkg.name, path: pkg_path, packageType: pkg_type)
        end

        PackagesPayload.new(
          packageCount: package_count,
          packages: serialized_packages,
          packagesPath: packages_url,
          canWrite: @current_repository.writable_by?(@current_user),
          publishPath: @current_repository.writable_by?(@current_user) ? packages_path(owner, @current_repository) : nil,
        )
      end

      sig { returns(T.nilable(UsedByPayload)) }
      def used_by_payload
        return nil unless @view_model.show_used_by_sidebar?

        result = Platform::Loaders::Dependencies.load_packages({
          package_filter: {
            repository_id: @current_repository.id,
            first: 1,
            package_id: @current_repository.used_by_package_id,
            preview: @current_repository.dependency_graph_preview?,
          },
          dependents_filter: {
            type: :repository,
            first: DEPENDENTS_LIMIT,
          },
          include_dependents: true,
        }).sync

        package = result.ok? ? result.value!.first : nil
        return nil unless package

        package.load_dependent_repositories(@current_user)
        num_dependents = package.repository_dependents_count || 0
        return nil if num_dependents < HIDE_USED_BY

        dependents = package.dependents.filter_map do |dep|
          repo = dep&.repository
          next unless repo&.owner

          UsedByItem.new(
            ownerLogin: repo.owner.display_login,
            avatarUrl: avatar_url_for(repo.owner, 64),
          )
        end

        owner = T.must(@current_repository.owner)
        UsedByPayload.new(
          dependentCount: num_dependents,
          dependents: dependents,
          dependentsPath: gh_network_dependents_package_path(@current_repository, package_id: package.id),
        )
      end

      sig { returns(T.nilable(ContributorsPayload)) }
      def contributors_payload
        count = @view_model.contributor_count

        contributors = @current_repository.top_contributors(
          limit: 14,
          viewer: @current_user,
          skip_bots: false,
        ).map do |user|
          ContributorItem.new(
            login: user.display_login,
            profileName: user.display_name.presence,
            profilePath: "/#{user.display_login}",
            avatarUrl: avatar_url_for(user, 64),
          )
        end

        ContributorsPayload.new(
          contributorCount: count,
          contributors: contributors,
          contributorsPath: gh_contributors_path(@current_repository),
        )
      end

      sig { returns(T.nilable(LanguagesPayload)) }
      def languages_payload
        return nil unless @view_model.show_languages?

        owner = @current_repository.owner
        languages = @view_model.top_languages.map do |lang_name, percentage|
          lang = Linguist::Language[lang_name]
          LanguageBreakdown.new(
            name: lang ? lang.name : lang_name,
            percentage: percentage.round(1),
            color: language_color(lang),
            searchAlias: lang&.default_alias,
          )
        end

        LanguagesPayload.new(
          languages: languages,
          isFork: @current_repository.fork?,
          ownerLogin: owner&.display_login || "",
          repoName: @current_repository.name,
        )
      end

      SUGGESTED_WORKFLOW_SECTION_NOTICE_NAME = "repo_suggested_workflows"
      MAX_NUM_OF_RECOMMENDED_TEMPLATES = 3

      sig { returns(T.nilable(SuggestedWorkflowsPayload)) }
      def suggested_workflows_payload
        return nil if GitHub.enterprise?
        return nil unless @current_user

        owner = @current_repository.owner
        if (organization = @current_repository.organization)
          return nil if organization.members_count > 100
          return nil if organization.invoiced?
        end

        return nil if @current_user.spammy?
        return nil if @current_user.dismissed_repository_notice?(SUGGESTED_WORKFLOW_SECTION_NOTICE_NAME, repository_id: @current_repository.id)
        return nil if @current_repository.actions_disabled_at_any_level?
        return nil unless @current_repository.writable_by?(@current_user)
        return nil if Actions::WorkflowRun.limit_execution_time.exists?(repository: @current_repository)

        templates = suggested_templates
        return nil if templates.size < 2

        branch = @current_repository.default_branch
        workflow_items = templates.each_with_index.map do |template, index|
          SuggestedWorkflowItem.new(
            id: template.id,
            name: template.name,
            description: template.description,
            creator: template.creator_name.presence || owner&.safe_profile_name || "",
            iconName: template.icon_name,
            iconRawUrl: template.icon_raw_url,
            langColor: template.lang_color,
            configurePath: new_file_path(owner, @current_repository, branch, filename: template.default_file_name, workflow_template: template.id),
            rank: index + 1,
          )
        end

        SuggestedWorkflowsPayload.new(
          workflows: workflow_items,
          moreWorkflowsPath: actions_onboarding_path(owner, @current_repository),
          dismissPath: dismiss_repository_notice_user_path(@current_user),
          noticeName: SUGGESTED_WORKFLOW_SECTION_NOTICE_NAME,
          repositoryId: @current_repository.id,
        )
      end

      sig { returns(T.nilable(CTAPayload)) }
      def cta_payload
        return nil unless @current_user
        return nil unless cta_viewable?

        owner = T.must(@current_repository.owner)
        tree_name = @current_repository.default_branch
        is_org = owner.organization?
        is_org_member_profile = is_org ? @current_repository.is_org_member_profile_repository? : false
        is_private = @current_repository.private?
        alternate_config = feature_enabled_globally_or_for_user?(feature_name: :alternate_user_config_repo, subject: owner)

        opted_in = if is_org
          true
        else
          @current_user.profile_readme_opt_in?
        end

        readme = resolve_readme(is_org: is_org, is_org_member_profile: is_org_member_profile, alternate_config: alternate_config)
        has_readme = !readme.nil?

        readme_display_path = if alternate_config
          @current_repository.expected_profile_readme_path
        else
          is_org ? "/profile/README.md" : "README.md"
        end

        add_readme_param = if alternate_config
          "profile_readme"
        elsif !is_org
          "readme"
        elsif is_org_member_profile
          "org_member_profile_readme"
        else
          "org_profile_readme"
        end

        add_readme_url = blob_new_path("", tree_name, @current_repository) + "?#{add_readme_param}=1"
        edit_readme_url = has_readme ? blob_edit_path(readme.path, tree_name, @current_repository) : nil

        settings_url = if opted_in && is_private && !is_org_member_profile
          edit_repository_path(owner, @current_repository, params: { return_to: repository_path(@current_repository) })
        end

        profile_url = is_org ? org_root_path(owner) : user_path(@current_user)

        opt_in_url = unless opted_in
          post_profile_readme_opt_in_path(user_id: @current_user.id)
        end

        owner_profile_name = if is_org_member_profile
          owner.safe_profile_name
        end

        CTAPayload.new(
          repoNameWithOwner: @current_repository.name_with_display_owner,
          isPrivate: is_private,
          isOrganization: is_org,
          isOrgMemberProfile: is_org_member_profile,
          optedIn: opted_in,
          hasReadme: has_readme,
          readmePath: readme_display_path,
          addReadmePath: add_readme_url,
          editReadmePath: edit_readme_url,
          settingsPath: settings_url,
          profilePath: profile_url,
          optInPath: opt_in_url,
          ownerProfileName: owner_profile_name,
        )
      end

      sig { returns(T.nilable(CitationPayload)) }
      def citation_payload
        citation = Repositories::Citation.from_repository(@current_repository)
        return nil unless citation&.valid?

        apa = citation.format(:apa)
        bibtex = citation.format(:bibtex)
        return nil unless apa || bibtex

        CitationPayload.new(
          apa: apa,
          bibtex: bibtex,
          filePath: citation.file_path,
          helpUrl: Repositories::Citation.help_url,
        )
      rescue StandardError
        nil
      end

      private

      # Wraps a section payload call so that any error returns nil instead of
      # crashing the entire unified response. Mirrors the Rails sidebar's
      # `render_nothing_on_error` behaviour.
      sig { type_parameters(:T).params(block: T.proc.returns(T.type_parameter(:T))).returns(T.nilable(T.type_parameter(:T))) }
      def resilient_section(&block)
        block.call
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        nil
      rescue StandardError => e
        Failbot.report(e)
        nil
      end

      # Wraps a boolean section-config check so that any error returns false
      # instead of crashing the about payload. Mirrors the Rails sidebar's
      # `render_nothing_on_error` wrapping around each section guard.
      sig { params(block: T.proc.returns(T::Boolean)).returns(T::Boolean) }
      def resilient_flag(&block)
        block.call
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        false
      rescue StandardError => e
        Failbot.report(e)
        false
      end

      # Returns release and tag counts when the releases section is enabled,
      # or false otherwise. tag_count is already cached by GitRPC;
      # release_count is an indexed COUNT query (fast for most repos).
      sig { returns(T.any(ReleaseSectionCounts, FalseClass)) }
      def releases_counts
        return false unless @view_model.releases_sidebar_section_enabled?

        ReleaseSectionCounts.new(
          releaseCount: @view_model.release_count,
          tagCount: @view_model.tag_count,
        )
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        false
      rescue StandardError => e
        Failbot.report(e)
        false
      end

      sig { returns(T.nilable(String)) }
      def pages_url
        @current_repository.page&.url&.to_s
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        nil
      end

      sig { params(owner: T.nilable(User)).returns(T.nilable(String)) }
      def custom_properties_path(owner)
        return nil unless owner&.organization? && @view_model.show_insights?

        repository_custom_properties_overview_path(owner, @current_repository)
      end

      sig { params(owner: T.nilable(User)).returns(T.nilable(String)) }
      def audit_log_path(owner)
        return nil unless @view_model.can_view_organization_audit_log_link?

        settings_org_audit_log_path(owner, q: "repo:#{@current_repository.name_with_display_owner}")
      end

      sig { returns(T.nilable(TemplateRepoInfo)) }
      def template_repository_info
        template_repo = @current_repository.template_repository
        return nil unless template_repo
        return nil if !@current_user && !template_repo.public?
        return nil unless template_repo.readable_by?(@current_user)

        TemplateRepoInfo.new(
          ownerLogin: template_repo.owner&.display_login || "",
          name: template_repo.name,
          path: repository_path(template_repo),
        )
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        nil
      end

      sig { params(owner: T.nilable(User)).returns(T.nilable(String)) }
      def report_path(owner)
        return nil unless @current_repository.can_report?(@current_user)

        flavored_contact_path(
          flavor: "report-content",
          report: "#{owner&.display_login} (user)",
          content_url: "#{GitHub.url}#{repository_path(@current_repository)}",
        )
      end

      # Returns true when the current user should see the configuration repo CTA.
      # Mirrors the render? logic from ConfigurationRepositoryCallToActionComponent.
      sig { returns(T::Boolean) }
      def cta_viewable?
        return false unless @current_user

        owner = @current_repository.owner
        alternate_config = feature_enabled_globally_or_for_user?(feature_name: :alternate_user_config_repo, subject: owner)

        # User's own profile repo
        if owner == @current_user
          return alternate_config ? @current_repository.profile_configuration_repository? : @current_repository.user_configuration_repository?
        end

        # Org profile or org member profile repo (admin only)
        return false unless owner&.organization?

        (@current_repository.is_org_profile_repository? || @current_repository.is_org_member_profile_repository?) &&
          @current_repository.adminable_by?(@current_user)
      end

      # Resolves the README blob for the configuration repository, following
      # the same logic as ConfigurationRepositoryCallToActionComponent#readme.
      sig { params(is_org: T::Boolean, is_org_member_profile: T::Boolean, alternate_config: T::Boolean).returns(T.nilable(TreeEntry)) }
      def resolve_readme(is_org:, is_org_member_profile:, alternate_config:)
        if alternate_config
          @current_repository.profile_readme
        elsif !is_org
          @current_repository.preferred_readme
        elsif is_org_member_profile
          @current_repository.org_member_profile_readme
        else
          @current_repository.org_profile_readme
        end
      end

      sig { returns(T::Array[RepositoryActions::Onboarding::Template]) }
      def suggested_templates
        template_recommender = Actions::WorkflowTemplate::Recommender.new(@current_repository, @current_user)
        templates = template_recommender.get_repo_based_templates(
          template_source: Actions::WorkflowTemplate::Source::ALL,
          filter_categories: ["Continuous integration"],
        )
        templates.delete_if { |template| template.id == "datadog-synthetics" }
        templates.max_by(MAX_NUM_OF_RECOMMENDED_TEMPLATES) { |template| rand**(1.0 / template.weight) }
      end
    end

    ## Payload Structs

    class Topic < T::Struct
      const :name, String
    end

    class TemplateRepoInfo < T::Struct
      const :ownerLogin, String
      const :name, String
      const :path, String
    end

    class ReleaseSectionCounts < T::Struct
      const :releaseCount, Integer
      const :tagCount, Integer
    end

    class SectionsConfig < T::Struct
      # false when disabled; a hint with counts when enabled
      const :releases, T.any(ReleaseSectionCounts, FalseClass)
      const :sponsors, T::Boolean
      # false when disabled; an array of environment names when enabled (may be empty)
      const :deployments, T.any(T::Boolean, T::Array[String])
      const :packages, T::Boolean
      const :usedBy, T::Boolean
      const :contributors, T::Boolean
      const :languages, T::Boolean
      const :cta, T::Boolean
      const :suggestedWorkflows, T::Boolean
    end

    class CitationPayload < T::Struct
      const :apa, T.nilable(String)
      const :bibtex, T.nilable(String)
      const :filePath, T.nilable(String)
      const :helpUrl, String
    end

    class AboutPayload < T::Struct
      const :description, T.nilable(String)
      const :formattedDescription, T.nilable(String)
      const :website, T.nilable(String)
      const :topics, T::Array[Topic]
      const :showInsights, T::Boolean
      const :stargazerCount, Integer
      const :watcherCount, Integer
      const :forksCount, Integer
      const :stargazersPath, String
      const :watchersPath, String
      const :forkNetworkPath, String
      const :activityPath, T.nilable(String)
      const :customPropertiesPath, T.nilable(String)
      const :auditLogPath, T.nilable(String)
      const :reportPath, T.nilable(String)
      const :canEditMetadata, T::Boolean
      const :ownerLogin, String
      const :repoName, String
      const :isOrg, T::Boolean
      const :sections, SectionsConfig
      const :hasCitation, T::Boolean
      const :pagesUrl, T.nilable(String)
      const :templateRepository, T.nilable(TemplateRepoInfo)
    end

    class LatestRelease < T::Struct
      const :name, String
      const :path, String
      const :publishedAt, T.nilable(String)
    end

    class ReleasesPayload < T::Struct
      const :latestRelease, T.nilable(LatestRelease)
      const :releasesPath, String
      const :tagsPath, String
      const :canWrite, T::Boolean
      const :newReleasePath, T.nilable(String)
    end

    class FundingLink < T::Struct
      const :platform, String
      const :url, String
      const :iconUrl, T.nilable(String)
      const :label, String
    end

    class SponsorableUser < T::Struct
      const :login, String
      const :displayName, T.nilable(String)
      const :profilePath, String
      const :avatarUrl, String
      const :isSponsoredByViewer, T::Boolean
    end

    class SponsorsPayload < T::Struct
      const :sponsorables, T::Array[SponsorableUser]
      const :externalFundingLinks, T::Array[FundingLink]
      const :sponsorsPath, String
      const :sponsorsLearnMorePath, String
      const :sponsorableCount, Integer
    end

    class DeploymentEnvironment < T::Struct
      const :name, String
      const :state, String
      const :createdAt, T.nilable(String)
      const :path, String
    end

    class DeployToPagesInfo < T::Struct
      const :framework, String
      const :frameworkLabel, String
      const :packageManager, String
      const :deployPath, String
      const :dismissPath, String
      const :noticeName, String
      const :repositoryId, Integer
    end

    class DeploymentsPayload < T::Struct
      const :environments, T::Array[DeploymentEnvironment]
      const :deploymentsPath, String
      const :deployToPages, T.nilable(DeployToPagesInfo)
      const :totalDeploymentCount, T.nilable(Integer)
    end

    class PackageItem < T::Struct
      const :name, String
      const :path, String
      const :packageType, String
    end

    class PackagesPayload < T::Struct
      const :packageCount, Integer
      const :packages, T::Array[PackageItem]
      const :packagesPath, String
      const :canWrite, T::Boolean
      const :publishPath, T.nilable(String)
    end

    class UsedByItem < T::Struct
      const :ownerLogin, String
      const :avatarUrl, String
    end

    class UsedByPayload < T::Struct
      const :dependentCount, Integer
      const :dependents, T::Array[UsedByItem]
      const :dependentsPath, String
    end

    class ContributorItem < T::Struct
      const :login, String
      const :profileName, T.nilable(String)
      const :profilePath, String
      const :avatarUrl, String
    end

    class ContributorsPayload < T::Struct
      const :contributorCount, Integer
      const :contributors, T::Array[ContributorItem]
      const :contributorsPath, String
    end

    class LanguageBreakdown < T::Struct
      const :name, String
      const :percentage, Float
      const :color, String
      const :searchAlias, T.nilable(String)
    end

    class LanguagesPayload < T::Struct
      const :languages, T::Array[LanguageBreakdown]
      const :isFork, T::Boolean
      const :ownerLogin, String
      const :repoName, String
    end

    class SuggestedWorkflowItem < T::Struct
      const :id, String
      const :name, String
      const :description, T.nilable(String)
      const :creator, String
      const :iconName, String
      const :iconRawUrl, T.nilable(String)
      const :langColor, String
      const :configurePath, String
      const :rank, Integer
    end

    class SuggestedWorkflowsPayload < T::Struct
      const :workflows, T::Array[SuggestedWorkflowItem]
      const :moreWorkflowsPath, String
      const :dismissPath, String
      const :noticeName, String
      const :repositoryId, Integer
    end

    class CTAPayload < T::Struct
      const :repoNameWithOwner, String
      const :isPrivate, T::Boolean
      const :isOrganization, T::Boolean
      const :isOrgMemberProfile, T::Boolean
      const :optedIn, T::Boolean
      const :hasReadme, T::Boolean
      const :readmePath, String
      const :addReadmePath, String
      const :editReadmePath, T.nilable(String)
      const :settingsPath, T.nilable(String)
      const :profilePath, String
      const :optInPath, T.nilable(String)
      const :ownerProfileName, T.nilable(String)
    end

    class FullSidebarPayload < T::Struct
      const :releases, T.nilable(ReleasesPayload)
      const :sponsors, T.nilable(SponsorsPayload)
      const :deployments, T.nilable(DeploymentsPayload)
      const :packages, T.nilable(PackagesPayload)
      const :usedBy, T.nilable(UsedByPayload)
      const :contributors, T.nilable(ContributorsPayload)
      const :languages, T.nilable(LanguagesPayload)
      const :suggestedWorkflows, T.nilable(SuggestedWorkflowsPayload)
      const :configCallToAction, T.nilable(CTAPayload)

      # T::Struct#serialize omits nil-valued keys. Override to always
      # include every declared prop so the JSON contract is stable.
      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        result = super
        self.class.props.each_key { |key| result[key.to_s] = nil unless result.key?(key.to_s) }
        result
      end
    end
  end
end
