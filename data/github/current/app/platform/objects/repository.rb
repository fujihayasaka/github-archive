# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Repository < Platform::Objects::Base
      include UrlHelper
      include GitHub::UTF8
      include Objects::Base::RecordObjectAccess
      include StacksHelper
      include Helpers::ProjectV2Sorter
      include IssuesHelper
      include GitHub::Tracing
      include GitHub::ResilienceMixin
      include NewsiesControllerHelper
      include Marketplace::Domain::Provider
      include Platform::Helpers::SearchHelper

      trace_method :dependency_graph_manifests

      description "A repository contains the content for a project."

      implements_node templates: [[:r, :id]],
        # TODO These `allow_nil_for: ...` configs are because some Hydro instrumentation
        # tries to build Global IDs for non-persisted (or deleted?) objects. Try removing that config,
        # and fix any broken tests to make sure that Hydro instrumentation will still work
        as: "R", allow_nil_for: [:id], ready_date: Platform::Helpers::GlobalId::COHORT_4 do |repo|
          { prefix: :r, id: repo.id }
        end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repo)
        promises = T.let([
          repo.async_owner,
          repo.async_parent,
          repo.async_internal_repository,
          repo.async_root,
          repo.async_ip_restricted_private_fork?,
        ], T::Array[Promise[T.untyped]])

        Promise.all(promises).then do |owner, _, _, _, ip_restricted_private_fork|
          next false unless owner

          if owner.is_a?(::Organization)
            current_org = owner
          end

          if ip_restricted_private_fork
            network_owner = repo.network_owner
            if network_owner.is_a?(::Organization)
              next false unless permission.access_allowed?(:v4_get_repo, repo: repo, current_org: network_owner, resource: repo, from_invitation: true, allow_integrations: true, allow_user_via_granular_actor: false)
            end
          end

          public_origin = permission.viewer && permission.public_origin?

          # Preload readable_by to avoid N+1 queries when checking access with access_allowed?
          if public_origin
            readable_by_promise = repo.resources.metadata.async_readable_by?(permission.viewer)
            if permission.integration_user_request? && permission.installation&.bot
              readable_by_promise = readable_by_promise.then { repo.resources.metadata.async_readable_by?(permission.installation.bot) }
            end
          end

          promises = [readable_by_promise]
          promises << repo.async_advisory_workspace? if public_origin

          Promise.all(promises).then do |_, _|
            next true if permission.access_allowed?(:v4_get_repo, repo: repo, current_org: current_org, resource: repo, from_invitation: false, allow_integrations: true, allow_user_via_granular_actor: true)

            Loaders::RepositoryInvitation.load(permission.viewer, repo).then do |invitation|
              # in this case, the invited user cannot read the metadata yet, but a subset is ok.
              next false unless invitation.present?

              permission.access_allowed?(:v4_get_repo, repo: repo, current_org: current_org, resource: repo, from_invitation: true, allow_integrations: true, allow_user_via_granular_actor: false)
            end
          end
        end.then do |access_allowed|
          next access_allowed if repo.public?

          if access_allowed && permission.external_request? && (repo.trade_restricted? || permission.viewer&.has_any_trade_restrictions?)
            # Only raise if the viewer has the right permissions
            raise Errors::TradeControls.new(repo.trade_restriction_api_error_message(permission.viewer))
          end

          access_allowed
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_visible_and_readable_by?(permission.viewer)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::ProjectNextRecent
      implements Interfaces::ProjectV2Recent
      implements Interfaces::ProjectOwner
      implements Interfaces::PackageOwner
      implements Interfaces::PackageSearch
      implements Interfaces::Subscribable
      implements Interfaces::Starrable
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::RepositoryInfo
      implements Interfaces::FeatureFlaggable
      implements Interfaces::ForkPrWorkflowsPolicy
      implements Interfaces::PublicForkPrWorkflowsPolicy
      implements Interfaces::DefaultWorkflowPermissions
      implements Interfaces::MarkdownPreviewable
      implements Interfaces::Searchable

      # This needs to be gated behind the `enterprise_banners_repo_level` FF, but that's not possible because the
      # interface is also used in the organization and enterprise GQL objects, so the rep-level FF can't be used
      # inside the interface. This can be uncommented when the FF is fully enabled.

      # implements Interfaces::AnnouncementBanner

      database_id_field

      field :viewer_subscription_types, [Enums::CustomSubscriptionType], description: "If custom subscription this is the types of subscriptions subscribed", null: true, required_capabilities: [:mobile_only_schema_mask]

      def viewer_subscription_types
        @object.async_subscription_status(@context[:viewer]).then do |subscription_status_response|
          if subscription_status_response.failed?
            raise Platform::Errors::ServiceUnavailable.new("Subscriptions are currently unavailable. Please try again later.")
          end

          subscription = subscription_status_response.value

          next [] unless subscription.thread_types.any?

          subscription.thread_types
        end
      end

      field :is_viewers_favorite, Boolean, description: "Is this repository added to the viewers favorites.", required_capabilities: [:mobile_only_schema_mask], null: false

      def is_viewers_favorite
        Dashboard.domain.repo_pinned_by_user(@object.id, @context[:viewer].id)
      end

      field :network, Objects::RepositoryNetwork, method: :async_network, visibility: :internal, description: "The repository network.", null: true

      field :readme, Objects::RepositoryReadme, method: :async_preferred_readme, required_capabilities: [:mobile_only_schema_mask], description: "The repository readme.", null: true do
        argument :ref_name, String, "The ref name used to return the associated readme.", required: false
      end

      field :template_repository, Repository,
            description: "The repository from which this repository was generated, if any.", null: true

      def template_repository
        @object.async_template_repository.then do |template_repo|
          next unless template_repo.present?

          template_repo.async_visible_and_readable_by?(@context[:viewer]).then do |visible|
            next unless visible
            template_repo
          end
        end
      end

      field :parent, Repository, description: "The repository parent, if this is a fork.", null: true

      def parent
        Platform::Loaders::EntityReference.load(@object, :parent).then do |parent|
          if parent&.disabled_at.nil?
            Loaders::ActiveRecord.load(::Repository, @object.parent_id, security_violation_behaviour: :nil).then do |repo|
              next nil unless repo.present?

              repo.async_owner.then do |owner|
                repo if owner.present?
              end
            end
          else
            nil
          end
        end
      end

      field :is_empty, Boolean, method: :async_empty?, description: "Returns whether or not this repository is empty.", null: false

      field :is_disabled, Boolean, description: "Returns whether or not this repository disabled.", null: false

      def is_disabled
        @object.async_disabled?(viewer: @context[:viewer])
      end

      field(
        :is_advisory_workspace,
        Boolean,
        method: :advisory_workspace?,
        description: "Whether or not this repository is an advisory workspace.",
        visibility: :internal,
        null: false,
      )

      field :should_upsell_ci, Boolean, "Whether or not this repository has continuous integration setup and should upsell ci.", required_capabilities: [:mobile_only_schema_mask], null: false

      def should_upsell_ci
        return false if @object.advisory_workspace?
        return false if marketplace_domain.repository_settings.has_ci?(@object)
        @object.adminable_by?(@context[:viewer])
      end

      field :sparkle_keyword, String, method: :async_sparkle_keyword, visibility: :internal, description: "The keyword used to create a sparkle", null: false

      field :actions_plan_owner, Objects::ActionsPlanOwner, method: :async_actions_plan_owner, visibility: :internal, description: "Returns the entity used by Actions Runtime for limiting build concurrency.", null: true

      field :allows_all_actions, Boolean, method: :async_allows_all_actions?, visibility: :internal, description: "Returns whether or not this repository allows all Actions to be used in a workflow.", null: false

      field :is_actions_disabled_at_any_level, Boolean, method: :async_actions_disabled_at_any_level?, visibility: :internal, description: "Returns whether or not Actions have been disabled in the repository, organization or enterprise settings", null: false

      # Used by Launch App to determine if Actions can run for this repo.
      field :is_actions_eligible, Boolean, visibility: :internal, description: "Repo's eligibility to use Actions", null: false

      def is_actions_eligible
        @object.async_owner.then do |owner|
          owner.async_customer.then do
            Billing::ActionsPermission.new(owner).allowed?(public: @object.public?)
          end
        end
      end

      field :is_actions_disabled_by_owner, Boolean, visibility: :internal, description: "Returns whether or not Actions have been disabled in the organization and enterprise scopes", null: false

      def is_actions_disabled_by_owner
        @object.actions_disabled_by_owner?
      end

      field :action_invocation_blocked, Boolean, method: :action_invocation_blocked?, visibility: :internal, description: "Returns whether or not GitHub Actions is allowed to be invoked", null: false

      field :has_listable_action, Boolean, visibility: :internal, method: :listable_action?, null: false, description: "Returns whether or not the repository has an Action that is listable on the Marketplace."

      field :has_action_at_root, Boolean, visibility: :internal, null: false, description: "Returns whether or not the repository has an action YAML file in its root."

      def has_action_at_root
        @object.action_at_root.present?
      end

      field :listed_action, Objects::RepositoryAction, method: :async_listed_action, null: true, visibility: :internal, description: "If one exists, the Action listed on the Marketplace for the repository."

      field :community_profile, Objects::CommunityProfile, method: :async_community_profile, visibility: :internal, description: "Information about the repository's community engagement.", null: true

      field :forks, resolver: Resolvers::Repositories, description: "A list of direct forked repositories.", connection: true

      field :commit_comments, resolver: Resolvers::CommitComments, description: "A list of commit comments associated with the repository.", connection: true

      field :installed_apps, Connections.define(App, name: "InstalledApp", edge_type: Edges::InstalledApp, visibility: :internal), visibility: :internal, description: "A list of installed GitHub Apps", null: false, connection: true

      def installed_apps
        Loaders::IntegrationInstallation::RepositoryForViewer.load(@object, @context[:viewer])
      end

      field :installed_app_installations, Connections.define(Objects::IntegrationInstallation, name: "InstalledAppInstallations", visibility: :internal), visibility: :internal,
            description: "A list of GitHub App Installations", null: false, connection: true do
        argument :is_assignable, Boolean, "Filter only installations that are assignable.", required: false, default_value: false, visibility: :internal
      end

      def installed_app_installations(is_assignable: false)
        Loaders::IntegrationInstallation::RepositoryForViewer.load(@object, @context[:viewer]).then do |installations|
          if is_assignable
            next ArrayWrapper.new([]) unless @object.feature_enabled?(:copilot_swe_agent)
            Promise.all(installations.map(&:async_integration)).then do |integrations|
              # TODO: replace with assignable? capability check
              integration = integrations.find { |i| i.slug == "copilot-swe-agent" }

              next ArrayWrapper.new([]) unless integration.present?
              next ArrayWrapper.new([]) if @object.public?

              ArrayWrapper.new([installations.find { |i| i.integration_id == integration.id }])
            end
          else
            installations
          end
        end
      end

      CONTRIBUTORS_DESCRIPTION = "A list of Users who have contributed to this repository from git. " +
        "Will return an empty list if not computable."

      field :contributors, Connections::RepositoryContributor,
        description: CONTRIBUTORS_DESCRIPTION, null: false, connection: true,
        required_capabilities: [:mobile_only_schema_mask], minimum_accepted_scopes: ["public_repo"]

      def contributors
        @object.async_enterprise_managed_business.then do
          Loaders::ActiveRecordAssociation.load(@object, :network).then do
            contributors_with_counts = @object.contributors(viewer: @context[:viewer], skip_private_profiles: true)
            if contributors_with_counts.computed?
              # [['defunkt', 1], ['mojombo', 1]]
              contributors_array = contributors_with_counts.value
              contributor_objects = contributors_array.map do |(user, count)|
                Platform::Models::UserContribution.new(user, count)
              end
              ArrayWrapper.new(contributor_objects)
            else
              ArrayWrapper.new
            end
          end
        end
      end

      field :contributors_count, Integer, description: "The number of contributors to this repository", null: false, required_capabilities: [:mobile_only_schema_mask], minimum_accepted_scopes: ["public_repo"]

      def contributors_count
        CommitContributions.domain.contributors_count_for_repository(@object)
      end

      TOP_CONTRIBUTORS_DESCRIPTION =
        "Users who have made the most commits to this repository. " +
        "Commit counts are not computed directly from git, results vary from the contributors field."

      field :top_contributors, [User], required_capabilities: [:mobile_only_schema_mask],  null: false, description: TOP_CONTRIBUTORS_DESCRIPTION do
        argument :limit, Integer, "How many contributors to return.", required: false, default_value: 5
        argument :skip_bots, Boolean, "Whether or not to skip bots.", required: false, default_value: false
        argument :skip_viewer, Boolean, "Whether or not to skip the viewer.", required: false, default_value: false
      end

      def top_contributors(limit:, skip_bots: false, skip_viewer: false)
        raise Errors::ArgumentLimit, "Only up to 100 contributors is supported." if limit > 100

        users = @object.top_contributors(
          limit: limit,
          viewer: @context[:viewer],
          skip_bots: skip_bots,
          skip_viewer: skip_viewer,
          skip_private_profiles: true,
        )

        ArrayWrapper.new(users)
      end

      field :deploy_keys, Connections.define(Objects::DeployKey), description: "A list of deploy keys that are on this repository.", null: false, connection: true

      def deploy_keys
        if @context[:permission].has_admin_resource_read_access?(resource: :deploy_keys, repo: @object)
          context[:permission].async_owner_if_org(object).then do |org|
            @object.async_organization.then do
              if context[:permission].access_allowed?(:list_repo_keys, repo: object, resource: object, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
                @object.async_public_keys.then do |public_keys|
                  ArrayWrapper.new(public_keys)
                end
              else
                ::PublicKey.none
              end
            end
          end
        else
          ::PublicKey.none
        end
      end

      field :admin_info, Objects::RepositoryAdminInfo, description: "Fields that are only visible to repo administrators.", null: true

      def admin_info
        Promise.all([@object.async_parent, @object.async_owner]).then do
          if @context[:viewer] && @object.adminable_by?(@context[:viewer])
            Models::RepositoryAdminInfo.new(@object)
          else
            nil
          end
        end
      end

      field :stafftools_info, Objects::RepositoryStafftoolsInfo, description: "Fields that are only visible to site admins.", null: true

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::RepositoryStafftoolsInfo.new(@object)
        else
          nil
        end
      end

      field :interaction_ability, Objects::RepositoryInteractionAbility, description: "The interaction ability settings for this repository.", null: true

      def interaction_ability
        return if @object.private?

        @object.async_can_read_interaction_limits?(context[:viewer]).then do |can_read|
          next unless can_read
          Platform::Models::RepositoryInteractionAbility.new(@object)
        end
      end

      field :plan_supports, Boolean, null: false, required_capabilities: [:mobile_only_schema_mask] do
        description "Returns whether or not a repository's plan supports a feature."
        argument :feature, Enums::PlanFeature, "The plan feature to check", required: true
      end

      def plan_supports(feature:)
        Promise.all([@object.async_internal_repository, @object.async_business]).then do
          @object.async_plan_supports?(feature)
        end
      end

      field :plan_limit, Integer, null: false, required_capabilities: [:mobile_only_schema_mask] do
        description "Returns the limit for the repository's billing plan."
        argument :feature, Enums::PlanFeatureLimit, "The limit for the plan feature", required: true
      end

      def plan_limit(feature:)
        @object.async_internal_repository.then do
          @object.async_plan_limit(feature)
        end
      end

      field :plan_features, Objects::RepositoryPlanFeatures, description: "Returns information about the availability of certain features and limits based on the repository's billing plan.", null: false

      def plan_features
        Platform::Models::RepositoryPlanFeatures.new(@object)
      end

      field :viewer_is_plan_owner, Boolean, null: false, visibility: :internal, description: "Returns whether or not the current viewer is the repository's billing plan owner."

      def viewer_is_plan_owner
        return false unless context[:viewer]

        @object.async_plan_owner.then do |plan_owner|
          context[:viewer] == plan_owner
        end
      end

      field :is_stack_template, Boolean, null: false, description: "Returns whether repository is stack template or not", visibility: :internal

      def is_stack_template
        false
      end

      field :viewer_default_merge_method, Enums::PullRequestMergeMethod, null: false, description: "The last used merge method by the viewer or the default for the repository."

      def viewer_default_merge_method
        @object.default_merge_method_for(@context[:viewer])
      end

      field :viewer_default_commit_email, String, null: true, description: "The last commit email for the viewer."

      def viewer_default_commit_email
        possible_author_email_sources = [
          @context[:viewer].async_primary_user_email,
          @context[:viewer].async_primary_private_user_email,
          @context[:viewer].async_stealth_user_email,
          @context[:viewer].async_profile,
        ]

        Promise.all(possible_author_email_sources).then do
          @context[:viewer].default_author_email(@object)
        end
      end

      field :viewer_possible_commit_emails, [String], null: true, description: "A list of emails this viewer can commit with."

      def viewer_possible_commit_emails
        possible_author_email_sources = [
          @context[:viewer].async_primary_user_email,
          @context[:viewer].async_primary_private_user_email,
          @context[:viewer].async_stealth_user_email,
          @context[:viewer].async_profile,
        ]

        Promise.all(possible_author_email_sources).then do
          @context[:viewer].author_emails
        end
      end

      field :deleted_issue, Objects::DeletedIssue, visibility: :internal, description: "Returns a single deleted issue from the current repository by number.", null: true do
        argument :number, Integer, "The number for the issue to be returned.", required: true
      end

      def deleted_issue(**arguments)
        DeletedIssues::Public.by_number(arguments[:number], repository_id: @object.id)
      end

      field :issue_or_pull_request, Unions::IssueOrPullRequest, description: "Returns a single issue-like object from the current repository by number.", null: true do
        argument :number, Integer, "The number for the issue to be returned.", required: true
      end

      def issue_or_pull_request(**arguments)
        Loaders::IssueishByNumber.load(@object.id, arguments[:number]).then do |issueish|
          not_found_message = "Could not resolve to an issue or pull request with the number of #{arguments[:number]}."

          unless issueish
            raise Errors::NotFound, not_found_message
          end

          if !issueish.pull_request? && !@object.has_issues?
            raise Errors::NotFound, not_found_message
          end

          # IssueishByNumber loader doesn't do spam checks, so we do that here
          graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(issueish)
          @context[:permission].typed_can_see?(graphql_type_name, issueish).then do |readable|
            if readable
              issueish
            else
              raise Errors::NotFound, not_found_message
            end
          end
        end
      end

      sig { override.returns(T.nilable(T::Boolean)) }
      def logged_in?
        context[:viewer].present?
      end

      field :issue, Objects::Issue, null: true do
        description "Returns a single issue from the current repository by number."
        argument :number, Integer, "The number for the issue to be returned.", required: true
        argument :mark_as_read, Boolean, "Whether or not to mark the issue as read by the viewer.", required: false, visibility: :internal, default_value: false
      end

      def issue(number:, mark_as_read: false)
        not_found_message = "Could not resolve to an Issue with the number of #{number}."

        # If the repository has issues disabled, terminate early with not found
        if !@object.has_issues?
          raise Errors::NotFound, not_found_message
        end

        Loaders::IssueByNumber.load(@object.id, number).then do |issue|
          if issue.nil? || issue.pull_request_id
            raise Errors::NotFound, not_found_message
          end

          GitHub::PrefillAssociations.prefill_associations(issue, :repository, available_records: [@object])

          # IssueByNumber loader doesn't do spam checks, so we do that here
          @context[:permission].typed_can_see?("Issue", issue).then do |readable|
            if readable
              if mark_as_read
                async_mark_thread_as_read issue, user: context[:viewer]
              end

              issue
            else
              raise Errors::NotFound, not_found_message
            end
          end
        end
      end

      field :issues, resolver: Resolvers::Issues, description: "A list of issues that have been opened in the repository.", connection: true

      field :activity, resolver: Resolvers::RepositoryActivities,
        description: "Lists a detailed history of changes to a repository, such as pushes, merges, force pushes, and branch changes, and associates these changes with commits and users.",
        connection: true,
        visibility: :internal

      field :discussions_count, Integer, null: false, required_capabilities: [:mobile_only_schema_mask], description: "Count of the Discussions within this repository."

      def discussions_count
        @object.discussions.size
      end

      field :has_closable_discussions_enabled,
        Boolean,
        description: "Indicates if the closable discussions feature is enabled for this repository",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def has_closable_discussions_enabled
        # We have to preserve this so we don't break the mobile app
        true
      end

      field :has_nested_discussion_answers_enabled,
        Boolean,
        description: "Indicates if the marking nested comments as answers feature is enabled for this repository",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def has_nested_discussion_answers_enabled
        true
      end

      field :show_actions,
        Boolean,
        description: "Indicates if Actions can be shown for this repository",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def show_actions
        # We are excluding pending setups because we will not handle those cases on mobile.
        object.async_show_actions?(include_pending_setup: false)
      end

      field :show_first_time_contributor_banner,
        Boolean,
        visibility: :internal,
        null: true do
        description "Indicates if the first time contributor banner should be shown for this repository"
        argument :is_pull_requests, Boolean, "Whether the user is on the /pulls/ page or /issues/", required: true
      end

      def show_first_time_contributor_banner(is_pull_requests:)
        # Gracefully degrade the banner if we encounter an error
        with_database_error_fallback(fallback: -> { raise Platform::Errors::Execution, "Unknown error occured" }) do
          @object.async_owner.then do |owner|
            is_owner_enterprise_managed.then do |owner_managed|
              @object.show_first_time_contributor_banner?(repo_owner: owner, owner_managed: owner_managed, user: @context[:viewer], is_pull_requests: is_pull_requests)
            end
          end
        end
      end

      # TODO: Deprecate this field in favor of `RepositoryInfo.hasDiscussionsEnabled`
      field :is_discussions_enabled,
        Boolean,
        description: "Are discussions available on this repository?",
        method: :async_discussions_active?,
        null: false,
        required_capabilities: [:mobile_only_schema_mask]

      field :discussion_categories, Connections.define(Objects::DiscussionCategory), null: false, connection: true,
        description: "A list of discussion categories that are available in the repository." do
          argument :filter_by_assignable, Boolean, "Filter by categories that are assignable by the viewer.", required: false, default_value: false
        end

      def discussion_categories(filter_by_assignable:)
        return ::DiscussionCategory.none unless @object.discussions_active?

        @object.async_discussion_categories.then do
          if filter_by_assignable
            @object.available_discussion_categories_for_actor(@context[:viewer])
          else
            @object.available_discussion_categories
          end
        end
      end

      field :discussion_category, Objects::DiscussionCategory, null: true, description: "A discussion category by slug." do
        argument :slug, String, "The slug of the discussion category to be returned.", required: true
      end

      def discussion_category(slug:)
        not_found_message = "Could not resolve to a DiscussionCategory with the slug #{slug}."
        raise Platform::Errors::NotFound, not_found_message unless @object.discussions_active?
        @object.available_discussion_categories_for_actor(@context[:viewer]).find_by_slug(slug).tap do |category|
          raise Platform::Errors::NotFound, not_found_message if category.nil?
        end
      end

      field :discussion, Objects::Discussion, null: true do
        description "Returns a single discussion from the current repository by number."
        argument :number, Integer, "The number for the discussion to be returned.", required: true
      end

      def discussion(number:)
        not_found_message = "Could not resolve to a Discussion with the number of #{number}."

        unless @object.discussions_active?
          raise Errors::NotFound, not_found_message
        end

        Loaders::DiscussionByNumber.load(@object.id, number).then do |discussion|
          if discussion.nil?
            raise Errors::NotFound, not_found_message
          end

          # DiscussionByNumber loader doesn't do spam checks, so we do that here
          @context[:permission].typed_can_see?("Discussion", discussion).then do |readable|
            if readable
              discussion
            else
              raise Errors::NotFound, not_found_message
            end
          end
        end
      end

      field :discussions, Connections.define(Objects::Discussion), null: false, description: "A list of discussions that have been opened in the repository.", connection: true do
        argument :category_id,
          ID,
          description: "Only include discussions that belong to the category with this ID.",
          default_value: nil,
          required: false
        argument :states,
          [Enums::DiscussionState],
          description: "A list of states to filter the discussions by.",
          default_value: [],
          required: false
        argument :order_by, Inputs::DiscussionOrder,
          description: "Ordering options for discussions returned from the connection.",
          default_value: { field: "bumped_at", direction: "DESC" },
          required: false
        argument :answered, Boolean,
          description: "Only show answered or unanswered discussions",
          default_value: nil,
          required: false
      end

      def discussions(order_by:, category_id:, states:, answered:)
        return ::Discussion.none unless @object.discussions_active?

        scope = @object.discussions.filter_spam_for(@context[:viewer])

        if states.present?
          scope = scope.where(state: states)
        end

        if order_by
          field = order_by[:field]
          direction = order_by[:direction]
          scope = scope.order("discussions.#{field} #{direction}")
        end

        unless answered.nil?
          scope = if answered
            scope.answered
          else
            scope.unanswered
          end
        end

        if category_id.present?
          not_found_message = "Unable to load discussion category with id of \"#{category_id}\""

          Helpers::NodeIdentification.async_typed_object_from_id(
            [Objects::DiscussionCategory], category_id, @context,
          ).then do |category|
            raise Platform::Errors::NotFound, not_found_message if @object != category.repository

            @context[:permission].typed_can_see?("DiscussionCategory", category).then do |readable|
              raise Platform::Errors::NotFound, not_found_message if !readable

              scope.where(category: category)
            end
          end
        else
          scope
        end
      end

      field :is_organization_discussion_repository, Boolean, null: false, required_capabilities: [:mobile_only_schema_mask], description: "Is this repository used for organization level discussion?"

      def is_organization_discussion_repository
        @object.async_organization_discussion.then { |discussion| discussion.present? }
      end

      field :viewer_has_blocked_contributors, Boolean, description: "Has the viewer blocked any contributors in this repository?", null: false, required_capabilities: [:mobile_only_schema_mask]

      def viewer_has_blocked_contributors(**arguments)
        @object.blocked_contributors_for(context[:viewer]).present?
      end

      field :pinned_discussions, Connections.define(Objects::PinnedDiscussion), description: "A list of discussions that have been pinned in this repository.", null: false

      def pinned_discussions
        return ArrayWrapper.new([]) unless @object.discussions_active?
        @object.discussion_spotlights
      end

      field :is_pinned, Boolean, visibility: :under_development, null: false,
            description: "Returns whether this repository is pinned to the profile of the specified repository owner." do
        argument :profile_owner_id, ID, "The ID of the owner of the profile you want to check.",
                 required: true
      end

      def is_pinned(profile_owner_id:)
        profile_owner = Helpers::NodeIdentification.
            typed_object_from_id([Interfaces::ProfileOwner], profile_owner_id, @context)
        profile_owner.pinned_repository?(@object)
      end

      field :pinned_issues, Connections.define(Objects::PinnedIssue), description: "A list of pinned issues for this repository.", null: true, connection: true

      def pinned_issues
        @object.async_pinned_issues.then do |pinned_issues|
          @object.async_owner.then do |owner|
            can_list_issues = context[:permission].can_list_issues?(owner, @object)
            return ArrayWrapper.new([]) unless can_list_issues

            hidden_from_user_promises = pinned_issues.map do |pinned_issue|
              pinned_issue.async_issue.then do |issue|
                issue.async_hide_from_user?(@context[:viewer])
              end
            end

            Promise.all(hidden_from_user_promises).then do |hidden_from_user|
              filtered_pins = pinned_issues.select.with_index { |_item, index| !hidden_from_user[index] }
              ArrayWrapper.new(filtered_pins.sort_by { |pin_issue| pin_issue.sort })
            end
          end
        end
      end

      field :pinned_environments, Connections.define(Objects::PinnedEnvironment), visibility: :public, description: "A list of pinned environments for this repository.", null: true, connection: true do
        argument :order_by, Inputs::PinnedEnvironmentOrder, "Ordering options for the environments", required: false, default_value: { field: "position", direction: "ASC" }
      end

      def pinned_environments(**arguments)
        return ::PinnedEnvironment.none unless @object.can_use_environments? || @object.can_see_deployments?(context[:viewer])

        order_by = arguments[:order_by]

        context[:permission].async_owner_if_org(@object).then do |_|
          if order_by = arguments[:order_by]
            return @object.pinned_environments.order(order_by[:field] => order_by[:direction])
          end

          @object.pinned_environments
        end
      end

      field :similar_issues, Connections.define(Objects::Issue), description: "A list of issues similar to a given query in the context of the repository.", null: false, connection: true, visibility: :under_development do
        argument :query, String, "The query to find similar issues.", required: true
      end

      def similar_issues(query:)
        @object.async_name_with_owner.then do |name_with_owner|
          # remove qualifiers from the string.
          # https://github.com/github/github/issues/99788
          sanitized_query = query.gsub(/@|:/, " ")
          phrase = "#{sanitized_query} repo:#{name_with_owner}"

          ::Search::Queries::SimilarIssueQuery.new \
            current_user: @context[:viewer],
            user_session: @context[:user_session],
            current_installation: @context[:installation],
            phrase: phrase,
            context: "graphql-related-issues"
        end
      end

      field :viewer_issue_creation_permissions, Objects::IssueCreationPermissions, visibility: :internal, description: "Returns the permissions the viewer has for creating issues in this repository.", null: false

      def viewer_issue_creation_permissions
        new_issue = ::Issue.new(repository: @object)
        Promise.all(async_issue_permissions(new_issue, @context[:viewer], @object)).then do |permissions|
          labelable, assignable, milestoneable, _closeable, _can_request_review, _can_re_request_review, triageable, typeable = permissions

          {
            labelable: labelable,
            assignable: assignable,
            milestoneable: milestoneable,
            triageable: triageable,
            typeable: typeable,
          }
        end.catch do |error|
          Failbot.report(error, "gh.repository.id": @object.id)
          {
            labelable: false,
            assignable: false,
            milestoneable: false,
            triageable: false,
            typeable: false,
          }
        end
      end

      field :branch_protection_rules, Connections.define(Objects::BranchProtectionRule), minimum_accepted_scopes: ["public_repo"], description: "A list of branch protection rules for this repository.", null: false, connection: true

      def branch_protection_rules
        Promise.all([@object.async_business, @object.async_organization, @object.async_internal_repository, @object.async_plan_customer]).then do
          # calling Promise.sync because sometimes return value is a Promise<bool> and sometimes it is bool
          has_access = Promise.sync(@context[:permission].has_admin_resource_read_access?(resource: :protected_branches, repo: @object)) # rubocop:disable GitHub/DontSyncInsideFields
          plan_supports = @object.plan_supports?(:protected_branches)
          next StableArrayWrapper.new([]) unless has_access && plan_supports

          @object.protected_branches
        end
      end

      field :ruleset, Objects::RepositoryRuleset,
        minimum_accepted_scopes: ["public_repo"],
        description: "Returns a single ruleset from the current repository by ID.",
        null: true do
          argument :include_parents, Boolean, "Include rulesets configured at higher levels that apply to this repository", required: false, default_value: true
          argument :database_id, Integer, "The ID of the ruleset to be returned.", required: true
        end

      def ruleset(**arguments)
        Promise.all([@object.async_organization, @object.async_business]).then do
          rulesets = ::RepositoryRuleset.load_for(source: @object, include_parents: arguments[:include_parents])
          # Return rulesets that are
          # 1. created by this source OR inherited enabled rulesets
          # 2. not a member privilege ruleset (branch, tag, push) OR is a member privilege ruleset and member privilege rulesets are enabled with provided feature flag
          #
          # check 2 can be removed when the `member_privilege_rulesets` ff is removed
          ruleset = rulesets
            .filter { |ruleset| (ruleset.enabled? || ruleset.source == @object) && (ruleset.target != "repository" || (@object.member_privilege_rulesets_enabled? && @context[:feature_flags].include?(:member_privilege_rulesets))) }
            .find { |ruleset| ruleset.id == arguments[:database_id] }
          if ruleset
            # track what node the query was from
            # which may be different from the true source of the ruleset if inherited
            ruleset.source_node = @object
          end
          ruleset
        end
      end

      field :rulesets, Platform::Connections::RepositoryRuleset,
        minimum_accepted_scopes: ["public_repo"],
        description: "A list of rulesets for this repository.",
        null: true,
        connection: true do
          argument :include_parents, Boolean, "Return rulesets configured at higher levels that apply to this repository", required: false, default_value: true
          argument :targets, [Enums::RepositoryRulesetTarget], "Return rulesets that apply to the specified target", required: false, default_value: nil
        end

      def rulesets(include_parents: nil, targets: nil)
        # Call async org because the organization association will eventually be called
        Promise.all([@object.async_organization, @object.async_business]).then do
          # Return rulesets that are
          # 1. created by this source OR inherited enabled rulesets
          # 2. not a member privilege ruleset (branch, tag, push) OR is a member privilege ruleset and member privilege rulesets are enabled with provided feature flag
          #
          # check 2 can be removed when the `member_privilege_rulesets` ff is removed
          rulesets = ::RepositoryRuleset.load_for(source: @object, include_parents:, targets:)
            .filter { |ruleset| (ruleset.enabled? || ruleset.source == @object) && (ruleset.target != "repository" || (@object.member_privilege_rulesets_enabled? && @context[:feature_flags].include?(:member_privilege_rulesets))) }
            .each { |ruleset| ruleset.source_node = @object }
          ArrayWrapper.new(rulesets)
        end
      end

      field :pull_request, Objects::PullRequest, description: "Returns a single pull request from the current repository by number.", null: true do
        argument :number, Integer, "The number for the pull request to be returned.", required: true
      end

      def pull_request(**arguments)
        Loaders::PullRequestByNumber.load(@object.id, arguments[:number]).then do |pull|
          if !pull || pull.hide_from_user?(@context[:viewer])
            raise Errors::NotFound, "Could not resolve to a PullRequest with the number of #{arguments[:number]}."
          end

          pull
        end
      end

      field :pull_requests, resolver: Resolvers::RepositoryPullRequests, description: "A list of pull requests that have been opened in the repository.", connection: true

      field :milestone, Milestone, description: "Returns a single milestone from the current repository by number.", null: true do
        argument :number, Integer, "The number for the milestone to be returned.", required: true
      end

      def milestone(**arguments)
        Loaders::MilestoneByNumber.load(@object.id, arguments[:number])
      end

      field :milestone_by_title, Milestone, visibility: :internal, description: "Returns a single milestone from the current repository by title.", null: true do
        argument :title, String, "The title for the milestone to be returned.", required: true
      end

      def milestone_by_title(**arguments)
        Loaders::MilestoneByTitle.load(@object.id, arguments[:title])
      end

      field :milestones, Connections.define(Objects::Milestone), description: "A list of milestones associated with the repository.", null: true, connection: true do
        argument :states, [Enums::MilestoneState], "Filter by the state of the milestones.", required: false
        argument :order_by, Inputs::MilestoneOrder, "Ordering options for milestones.", required: false
        argument :query, String, "Filters milestones with a query on the title", required: false
        argument :order_by_states, [Enums::MilestoneState], "Order by the state of the milestone, respecting orderBy", required: false, visibility: :internal
      end

      def milestones(**arguments)
        context[:permission].async_can_list_milestones?(@object).then do |can_list_milestones|
          if can_list_milestones
            milestones = @object.milestones

            if arguments[:states]
              milestones = milestones.where(state: arguments[:states])
            end

            if arguments[:query]
              query = ActiveRecord::Base.sanitize_sql_like(
                arguments[:query].to_s.strip.downcase
              )
              # Since title is a mediumblob column, we are not able to case-insensitive query on it using LIKE.
              # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
              milestones = milestones.where("CAST(title AS CHAR CHARACTER SET utf8mb4) LIKE ?", "%#{query}%") if query.present?
            end

            if arguments[:order_by_states].present?
              milestones = milestones.sorted_by_state(arguments[:order_by_states])
            end

            if order_by = arguments[:order_by]
              milestones = milestones.sorted_by(order_by[:field], order_by[:direction].downcase)
            end

            milestones.filter_spam_for(@context[:viewer])

          else # Not permitted to list milestones
            ::Milestone.none
          end
        end
      end

      field :label, Label, description: "Returns a single label by name", null: true do
        argument :name, String, "Label name", required: true
      end

      def label(**arguments)
        Loaders::LabelByName.load(@object.id, arguments[:name])
      end

      field :good_first_issue_label, Label, visibility: :internal, description: "Returns the label this repository uses to denote good issues for new users.", null: true

      field :help_wanted_label, Label, visibility: :internal, description: "Returns the label this repository uses to denote issues that need help.", null: true

      field :code_of_conduct, CodeOfConduct, description: "Returns the code of conduct for this repository", null: true

      def code_of_conduct
        @object.async_disabled_access_reason.then do
          if @object.detect_code_of_conduct
            @object.code_of_conduct
          else
            nil
          end
        end
      end

      field :watchers, resolver: Resolvers::Watchers, description: "A list of users watching the repository.", connection: true

      field :collaborators, Connections::RepositoryCollaborator, resolver: Resolvers::RepositoryCollaborators, description: "A list of collaborators associated with the repository.", null: true, connection: false do
        has_connection_arguments
      end

      field :labels, resolver: Resolvers::Labels, description: "A list of labels associated with the repository.", scope: true do
        argument :query, String, "If provided, searches labels by name and description.", required: false
      end

      field :languages, Connections::RepositoryLanguage, description: "A list containing a breakdown of the language composition of the repository.", null: true, connection: true do
        argument :order_by, Inputs::LanguageOrder, "Order for connection", required: false
      end

      def languages(order_by: nil)
        context[:permission].async_owner_if_org(@object).then do |org|
          if context[:permission].access_allowed?(:list_languages, resource: @object, current_repo: @object, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
            scope = ::Language.where(repository_id: @object.id)

            if order_by
              scope = scope.order(order_by[:field] => order_by[:direction])
            end

            scope
          else
            ::Language.none
          end
        end

      end

      field :viewer_permission, Enums::RepositoryPermission, description: "The users permission level on the repository. Will return null if authenticated as an GitHub App.", null: true

      def viewer_permission
        if @context[:viewer]&.user?
          @object.async_organization.then do
            @object.async_parent.then do
              permission = @object.role_based_access_level(@context[:viewer])
              permission ? permission.to_s : nil
            end
          end
        end
      end

      field :viewer_can_see_commenter_full_name, Boolean, description: "Can the viewer see comment author's full name", null: false, visibility: :under_development

      def viewer_can_see_commenter_full_name
        @object.async_viewer_can_see_commenter_full_name?(@context[:viewer])
      end

      field :primary_language, Language, method: :async_primary_language, description: "The primary language of the repository's code.", null: true

      field :has_heads, Boolean, visibility: :internal, description: "Returns a boolean indicating if the repository has branches or not.", null: false

      def has_heads
        @object.async_network.then do
          @object.heads.count > 0
        end
      end

      field :branches_including_default_first, [String], visibility: :internal, description: "Return the list of branches in the repository including the default one (first).", null: false

      def branches_including_default_first
        @object.async_network.then do
          @object.heads.refs_with_default_first.map do |branch|
            branch.name.force_encoding("UTF-8")
          end
        end
      end

      field :ref, Objects::Ref, description: "Fetch a given ref from the repository", null: true do
        argument :qualified_name, String, "The ref to retrieve. Fully qualified matches are checked in order (`refs/heads/master`) before falling back onto checks for short name matches (`master`).", required: true
      end

      def ref(**arguments)
        @object.async_network.then do
          @object.refs.find(arguments[:qualified_name])
        end
      end

      field :refs, Connections::Ref, resolver: Resolvers::Refs, description: "Fetch a list of refs from the repository", null: true, connection: true do
        argument :ref_prefix, String, "A ref name prefix like `refs/heads/`, `refs/tags/`, etc.", required: true
        argument :direction, Enums::OrderDirection, "DEPRECATED: use orderBy. The ordering direction.", required: false
        argument :order_by, Inputs::RefOrder, "Ordering options for refs returned from the connection.", required: false
      end

      field :commit_revision, Objects::CommitRevision, visibility: :internal, description: <<~MD, null: true do
          Find commit by extended SHA-1 syntax.

          Returns nothing if revision syntax is invalid.
      MD

        argument :name, String, <<~MD, required: true
          The name that can be resolved to a commit.

          See CommitRevision.name for examples.
        MD
      end

      def commit_revision(**arguments)
        Models::CommitRevision.find(@object, arguments[:name])
      end

      field :object, Interfaces::GitObject, description: "A Git object in the repository", null: true, resolver_method: :git_object do
        argument :oid, Scalars::GitObjectID, "The Git object ID", required: false

        argument :expression, String, "A Git revision expression suitable for rev-parse", required: false
      end

      def git_object(**arguments)
        oid = T.let(nil, T.nilable(String))
        context.scoped_merge!(root_commit_arguments: arguments)
        if arguments[:oid]
          oid = arguments[:oid]
          Platform::Loaders::GitObject.load(@object, oid)
        elsif arguments[:expression]
          # TODO - GitRPC doesn't have any batch rev-parse functionality at
          # the moment. When we implement that this should move to a loader.
          @object.async_network.then do
            begin
              if oid = @object.ref_to_sha(arguments[:expression])
                path_prefix = ::Commit.extract_path_prefix_from_expression(arguments[:expression])
                Platform::Loaders::GitObject.load(@object, oid, path_prefix: path_prefix)
              end
            rescue GitHub::DGit::UnroutedError => e
              nil
            end
          end
        end
      end

      field :mentionable_users, resolver: Resolvers::MentionableUsers, description: "A list of Users that can be mentioned in the context of the repository.", connection: true

      field :assignable_users, resolver: Resolvers::AssignableUsers, description: "A list of users that can be assigned to issues in this repository.", connection: true, numeric_pagination_enabled: true

      field :has_vulnerability_alerts_enabled, Boolean, method: :async_vulnerability_alerts_enabled?, description: "Whether vulnerability alerts are enabled for the repository.", null: false

      field :vulnerability_alert, Objects::RepositoryVulnerabilityAlert, description: "Returns a single vulnerability alert from the current repository by number.", null: true do
        argument :number, Integer, "The number for the vulnerability alert to be returned.", required: true
      end

      def vulnerability_alert(**arguments)
        context[:permission].async_can_list_vulnerability_alerts?(@object).then do |can_list_vulnerability_alerts|
          error_msg = "Could not resolve to a RepositoryVulnerabilityAlert with the number of #{arguments[:number]}."
          raise Errors::NotFound, error_msg unless can_list_vulnerability_alerts

          vulnerability_alert = @object.repository_vulnerability_alerts.find_by(number: arguments[:number])
          raise Errors::NotFound, error_msg unless vulnerability_alert

          vulnerability_alert
        end
      end

      field :vulnerability_alerts, Connections.define(Objects::RepositoryVulnerabilityAlert), description: "A list of vulnerability alerts that are on this repository.", null: true, connection: true do
        argument :states, [Enums::RepositoryVulnerabilityAlertState], "Filter by the state of the alert", required: false
        argument :dependency_scopes, [Enums::RepositoryVulnerabilityAlertDependencyScope], "Filter by the scope of the alert's dependency", required: false
      end

      def vulnerability_alerts(**arguments)
        context[:permission].async_can_list_vulnerability_alerts?(@object).then do |can_list_vulnerability_alerts|
          next ::RepositoryVulnerabilityAlert.none unless can_list_vulnerability_alerts

          # We only want to return vulnerability_alerts that have vulnerable_version_ranges
          # because they're necessary to render an API response. If they're missing, 500s will happen.
          vulnerability_alerts = @object.repository_vulnerability_alerts.has_vulnerable_version_range

          vulnerability_alerts = vulnerability_alerts.where(state: arguments[:states]) if arguments[:states]
          vulnerability_alerts = vulnerability_alerts.where(dependency_scope: arguments[:dependency_scopes]) if arguments[:dependency_scopes]

          vulnerability_alerts
        end
      end

      field :dependency_graph_manifests, Connections.define(Objects::DependencyGraphManifest), null: true,
            connection: false, # disable built-in connection wrapper because we're paginating ourselves.
            description: "A list of dependency manifests contained in the repository",
            extras: [:execution_errors, :lookahead] do
        has_connection_arguments
        argument :with_dependencies, Boolean, "Flag to scope to only manifests with dependencies", required: false
        argument :include_dependencies, Boolean, "Flag to indicate that dependencies should be eagerly loaded", required: false, default_value: true, visibility: :internal
        argument :dependencies_first, Integer, "Number of dependencies to fetch", required: false
        argument :dependencies_after, String, "Cursor to paginate dependencies", required: false
        argument :dependencies_prefers, [String, null: true], "Dependencies to return first", required: false, visibility: :internal
        argument :package_manager, String, "Package manager to scope to", required: false, visibility: :internal
        argument :package_name, String, "Package name to scope to", required: false, visibility: :internal
      end

      def dependency_graph_manifests(execution_errors:, lookahead:, **arguments)
        arguments[:include_dependencies] = true if arguments[:include_dependencies].nil?
        @context[:permission].async_can_list_dependency_graphs?(@object).then do |can_list_dependency_graphs|
          if !can_list_dependency_graphs
            # Not permitted to list dependency_graphs, return empty
            return ConnectionWrappers::ArrayWrapper.new(
              ArrayWrapper.new,
              first: arguments[:first],
              last: arguments[:last],
              before: arguments[:before],
              after: arguments[:after],
              arguments: arguments,
              parent: object,
              context: context
            )
          end

          @object.async_network.then do
            @object.async_owner.then do
              include_internal_snapshots = DependencyGraph.include_internal_snapshots?(@object)
              manifest_filter = {
                  repository_id: @object.id,
                  first: arguments[:first],
                  after: arguments[:after],
                  include_internal_snapshots: include_internal_snapshots,
                  with_dependencies: !!arguments[:with_dependencies],
                  preview: @object.dependency_graph_preview?,
              }
              if arguments[:package_name]
                manifest_filter[:package_name] = arguments[:package_name]
              end
              if arguments[:package_manager]
                manifest_filter[:package_manager] = arguments[:package_manager]
              end

              # This defaults to 'true' if not included as an argument
              include_dependencies = !!arguments[:include_dependencies]

              dependencies_selected = lookahead.selection(:edges).selection(:node).selects?(:dependencies) ||
                                      lookahead.selection(:nodes).selects?(:dependencies)

              GitHub.dogstats.increment("dependency_graph.graphql.dependency_graph_manifests", tags: ["dependencies_selected:#{dependencies_selected}"])

              # However, we can selectively disable it if we find out that we don't need the dependencies for this query
              if !dependencies_selected
                include_dependencies = false
              end

              Loaders::Dependencies.load_manifests(@object, {
                  manifest_filter: manifest_filter,
                  dependencies_filter: {
                      first: arguments[:dependencies_first],
                      after: arguments[:dependencies_after],
                      prefer: arguments[:dependencies_prefers],
                  },
                  include_dependencies: include_dependencies
              }).then do |result|
                if result.ok?
                  result = result.value!
                  wrapper = ConnectionWrappers::RepositoryDependencyManifests.new(
                    ArrayWrapper.new(result[:manifests]),
                    first: arguments[:first],
                    after: arguments[:after],
                    max_page_size: arguments[:max_page_size],
                    last: arguments[:last],
                    before: arguments[:before],
                    edge_class: arguments[:edge_class],
                    arguments: arguments,
                    parent: object,
                    context: context
                  )

                  wrapper.has_next_page = result[:page_info]["hasNextPage"]
                  wrapper.has_previous_page = result[:page_info]["hasPreviousPage"]
                  wrapper.start_cursor = result[:page_info]["startCursor"]
                  wrapper.end_cursor = result[:page_info]["endCursor"]
                  wrapper.total_count = result[:total_count]

                  wrapper.has_next_page = false if wrapper.has_next_page.nil?
                  wrapper.has_previous_page = false if wrapper.has_previous_page.nil?

                  wrapper
                else
                  message = case result.error
                  when ::Repository::DependenciesDependency::ManifestsNotDetectedError
                    "loading"
                  when ::DependencyGraph::Client::TimeoutError
                    "timedout"
                  when ::DependencyGraph::Client::ServiceUnavailableError, ::DependencyGraph::Client::ApiError, StandardError
                    "unavailable"
                  end
                  execution_errors.add(message)

                  # Apply a connection wrapper manually
                  ConnectionWrappers::ArrayWrapper.new(
                    ArrayWrapper.new,
                    first: arguments[:first],
                    last: arguments[:last],
                    before: arguments[:before],
                    after: arguments[:after],
                    arguments: arguments,
                    parent: object,
                    context: context,
                  )
                end
              end
            end
          end
        end
      end

      field :dependency_graph_packages, Connections.define(Objects::DependencyGraphPackage), null: true,
            visibility: :internal,
            description: "A list of packages contained in the repository",
            connection: false, # Opt out of this since we're implementing the connection directly
            extras: [:execution_errors] do
        has_connection_arguments
        argument :package_id, String, "The internal dependency graph package ID", required: false
        argument :include_dependents, Boolean, "Flag to indicate that dependents should be eagerly loaded", required: false
        argument :include_dependent_counts, Boolean, "Flag to indicate that dependent count should be loaded", required: false
        argument :dependent_type, Enums::DependencyGraphDependentType, "The type of dependent to query", required: false
        argument :dependents_first, Integer, "Number of dependents to fetch", required: false
        argument :dependents_after, String, "Cursor to paginate dependents", required: false
        argument :dependents_last, Integer, "Number of dependents to fetch", required: false
        argument :dependents_before, String, "Cursor to paginate dependents", required: false
        argument :debug, Boolean, "Debug packages data", required: false
      end

      def dependency_graph_packages(execution_errors:, **arguments)
        @object.async_owner.then do
          Loaders::Dependencies.load_packages({
                                                  package_filter: {
                                                      repository_id: @object.id,
                                                      package_id: arguments[:package_id],
                                                      first: arguments[:first],
                                                      debug: !!arguments[:debug],
                                                      preview: @object.dependency_graph_preview?,
                                                  },
                                                  dependents_filter: {
                                                      type: arguments[:dependent_type],
                                                      first: arguments[:dependents_first],
                                                      after: arguments[:dependents_after],
                                                      last: arguments[:dependents_last],
                                                      before: arguments[:dependents_before],
                                                  },
                                                  include_dependents: !!arguments[:include_dependents],
                                                  include_dependent_counts: !!arguments[:include_dependent_counts],
                                              }).then do |result|
            array_wrapper = result
                                .map { |value| ArrayWrapper.new(value) }
                                .value do |error|
                                  execution_errors.add(error.message)
                                  ArrayWrapper.new
                                end
            # Manually instantiate a connection since we skipped
            # the built-in wrapping with `connection: false` above
            Platform::ConnectionWrappers::ArrayWrapper.new(
                array_wrapper,
                first: arguments[:first],
                last: arguments[:last],
                before: arguments[:before],
                after: arguments[:after],
                arguments: arguments,
                parent: object,
                context: context,
            )
          end
        end
      end

      field :primary_page_deployment, Objects::PageDeployment, visibility: :internal, description: "The GitHub Pages site associated with the primary Pages source branch.", null: true

      def primary_page_deployment
        @object.async_page.then do |page|
          next unless page
          page.async_primary_deployment
        end
      end

      field :page_deployments, Connections.define(PageDeployment, visibility: :internal), visibility: :internal, description: "The GitHub Pages sites associated with this repository.", null: false, connection: true

      def page_deployments
        @object.async_page.then do |page|
          # No page? No problem. Return an empty array.
          next ArrayWrapper.new unless page
          page.async_deployments.then do |_deployments|
            @object.page.deployments.scoped
          end
        end
      end

      field :gh_pages_error, Boolean, visibility: :internal, null: true, description: "The build status for the last page deployment"

      def gh_pages_error
        @object.async_page.then do |page|
          page&.builds&.first&.error?
        end
      end

      field :gh_pages_error_message, String, visibility: :internal, null: true, description: "The error message for the last page build"

      def gh_pages_error_message
        @object.async_page.then do |page|
          next unless page && page.builds.any?
          page.builds.first.try(:error)
        end
      end

      field :has_page, Boolean, description: "does this repo have a page", null: false, visibility: :internal

      def has_page
        @object.async_page.then do |page|
          !!page
        end
      end

      field :page_source, String, description: "source for a Repository's page", null: true, visibility: :internal

      def page_source
        @object.async_page.then do |page|
          next unless page
          page.source_branch.dup.force_encoding("UTF-8")
        end
      end

      field :page_source_directory, String, description: "source directory for a Repository's page", null: true, visibility: :internal

      def page_source_directory
        @object.async_page.then do |page|
          next unless page
          page.source_dir
        end
      end

      field :is_user_pages_repo, Boolean, description: "is this a user pages repository", visibility: :internal, null: false, method: :async_is_user_pages_repo?

      field :cname_error, String, description: "The cname error for the associated page build", visibility: :internal, null: true

      def cname_error
        @object.async_page.then do |page|
          next unless page
          page.cname_error(page.cname)
        end
      end

      field :gh_pages_url, Scalars::URI, description: "the gh pages URL for this repo", visibility: :internal, null: true, method: :async_gh_pages_url

      field :org_members_can_create_pages, Boolean, description: "if repo is owned by org, does it allow members to create pages", visibility: :internal, null: false, method: :org_members_can_create_pages?

      url_fields prefix: :projects, description: "The HTTP URL listing the repository's projects" do |repository|
        "#{repository.permalink(include_host: false)}/projects"
      end

      field :releases, Connections.define(Objects::Release), description: "List of releases which are dependent on this repository.", null: false, connection: true do
        argument :order_by, Inputs::ReleaseOrder, "Order for connection", required: false
      end

      def releases(**arguments)
        context[:permission].async_can_list_releases?(@object).then do |can_list_releases|
          next ::Release.none unless can_list_releases

          @object.async_network.then do
            context[:permission].async_can_list_draft_releases?(@object).then do |can_list_draft_releases|
              # if the order by request is passed in, we can fetch releases from the database
              if order_by = arguments[:order_by]
                scope = can_list_draft_releases ? @object.releases.scoped : @object.releases.published
                scope = scope.order("releases.#{order_by[:field]} #{order_by[:direction]}")
                scope
              else
                # otherwise, we want to fetch releases from the API so that we go through ElasticSearch
                # we have an issue here that the GraphQL interface exposes connection arguments (first, last, after)
                # while ElasticSearch supports paging. We do not have this problem in REST because that interface
                # also uses pages. For now, we are querying for a limited number of results from ElasticSearch and then
                # letting the ArrayWrapper handle the connection arguments and filter the results to the requested
                # amount
                releases = ::Releases::Public.query_releases(@object, @context[:viewer], allow_drafts: can_list_draft_releases, limit: 1000).models
                ArrayWrapper.new(releases)
              end
            end
          end
        end
      end

      field :release, Objects::Release, description: "Lookup a single release given various criteria.", null: true do
        argument :tag_name, String, "The name of the Tag the Release was created from", required: true
      end

      def release(tag_name:)
        from_scope = @object.releases.from("releases FORCE INDEX (by_published)")
        release = from_scope.where(tag_name: tag_name).or(from_scope.where(pending_tag: tag_name)).first
        if release
          release.async_readable_by?(context[:viewer]).then do |is_readable|
            release if is_readable
          end
        end
      end

      field :latest_release, Objects::Release, description: "Get the latest release for the repository if one exists.", null: true

      def latest_release
        @object.async_network.then do
          @object.async_batch_latest_release(@context[:viewer])
        end
      end

      field :merge_queue, Objects::MergeQueue, description: "The merge queue for a specified branch, otherwise the default branch if not provided.", null: true, visibility: { public: { environments: [:dotcom, :enterprise] } } do
        argument :branch, String, "The name of the branch to get the merge queue for. Case sensitive.", required: false
      end

      def merge_queue(**arguments)
        if arguments[:branch].present?
          @object.async_merge_queue_for(branch: arguments[:branch])
        else
          @object.async_default_merge_queue
        end
      end

      field :repository_topics, Connections.define(Objects::RepositoryTopic), numeric_pagination_enabled: true, description: "A list of applied repository-topic associations for this repository.", null: false, connection: true

      def repository_topics(**arguments)
        @object.applied_repository_topics.scoped
      end

      field :disk_usage, Integer, description: "The number of kilobytes this repository occupies on disk.", null: true

      def disk_usage
        @context[:permission].async_can_get_full_repo?(@object).then do |can_get_full_repo|
          if can_get_full_repo
            @object.disk_usage
          else
            nil
          end
        end
      end

      field :viewer_can_update_topics, Boolean, description: "Indicates whether the viewer can update the topics of this repository.", null: false

      def viewer_can_update_topics
        Promise.all([@object.async_parent, @object.async_owner]).then do
          !@object.locked_on_migration? &&
              !@object.archived? &&
              @object.adminable_by?(@context[:viewer])
        end
      end

      field :viewer_can_administer, Boolean, description: "Indicates whether the viewer has admin permissions on this repository.", null: false

      def viewer_can_administer
        @object.async_adminable_by?(@context[:viewer])
      end

      field :viewer_can_interact, Boolean, visibility: :under_development,
            description: "Indicates whether the current user can interact according to repository interaction limits.", null: false

      def viewer_can_interact
        return false unless @context[:viewer]
        ::User::InteractionAbility.async_interaction_allowed?(user: @context[:viewer], repository: @object)
      end

      field :viewer_interaction_limit_reason_html,
        Scalars::HTML,
        visibility: :internal,
        description: "Provides the interaction limit reason for the current user or an empty string if they are not restricted. ",
        null: true

      def viewer_interaction_limit_reason_html
        return GitHub::HTMLSafeString::EMPTY unless @context[:viewer]
        with_async_database_error_fallback(
          ::User::InteractionAbility.async_interaction_allowed?(user: @context[:viewer], repository: @object).then do |is_allowed|
            next GitHub::HTMLSafeString::EMPTY if is_allowed

            ::RepositoryInteractionAbility.async_interaction_ban_copy(@object, @context[:viewer]).then do |copy|
              copy.html_safe # rubocop:disable Rails/OutputSafety
            end

          end,
          fallback: -> { raise Platform::Errors::ServiceUnavailable.new("Interaction unavailable - please try again later") }
        )
      end

      field :viewer_can_push, Boolean, required_capabilities: [:mobile_only_schema_mask],
            description: "Indicates whether the current user has push permissions on this repository.", null: false

      def viewer_can_push
        return false unless @context[:viewer]
        @object.async_pushable_by?(@context[:viewer])
      end

      field :viewer_blocked_by_owner, Boolean, required_capabilities: [:mobile_only_schema_mask],
            description: "Indicates whether the current user has been blocked by the repository owner.", null: false

      def viewer_blocked_by_owner
        return false if !@context[:viewer] || @context[:viewer].id == @object.owner_id
        @object.async_owner.then { |owner| @context[:viewer].async_blocked_by?(owner) }
      end

      field :viewer_can_pin_issues, Boolean, visibility: :internal,
            description: "Indicates whether the current user can pin and unpin issues to the repository", null: false

      def viewer_can_pin_issues
        return false if !@context[:viewer]
        @object.async_can_pin_issues?(@context[:viewer])
      end

      field :exported_to_url, Scalars::URI, visibility: :internal, description: "The URL to where this repository has been exported to or null if the repository is not locked for migration.", null: true

      def exported_to_url
        if @object.locked_on_migration?
          @object.async_configuration_owners.then do
            @object.get_repository_exported_to_url
          end
        end
      end

      field :network_present, Boolean, visibility: :internal, description: "Whether or not this repository's network is present on disk.", null: false

      def network_present
        @object.async_network.then do
          @object.network.present?
        end
      end

      field :default_branch_ref, Objects::Ref, description: "The Ref associated with the repository's default branch.", null: true, method: :async_default_branch_ref

      field :deployments, Connections.define(Objects::Deployment), description: "Deployments associated with the repository", null: false, connection: true, resolver: Resolvers::RepositoryDeployments

      field :squash_merge_allowed, Boolean, method: :async_squash_merge_allowed?, description: "Whether or not squash-merging is enabled on this repository.", null: false
      field :rebase_merge_allowed, Boolean, method: :async_rebase_merge_allowed?, description: "Whether or not rebase-merging is enabled on this repository.", null: false
      field :merge_commit_allowed, Boolean, method: :async_merge_commit_allowed?, description: "Whether or not PRs are merged with a merge commit on this repository.", null: false
      field :auto_merge_allowed, Boolean, method: :async_auto_merge_allowed?, description: "Whether or not Auto-merge can be enabled on pull requests in this repository.", null: false
      field :delete_branch_on_merge, Boolean, method: :async_delete_branch_on_merge?, description: "Whether or not branches are automatically deleted when merged in this repository.", null: false
      field :allow_update_branch, Boolean, method: :enable_update_branch?, description: "Whether or not a pull request head branch that is behind its base branch can always be updated even if it is not required to be up to date before merging.", null: false
      field :squash_pr_title_used_as_default, Boolean, method: :squash_pr_title_enabled?, description: "Whether a squash merge commit can use the pull request title as default.", null: false do
        deprecated(
          start_date: Date.new(2022, 12, 01),
          reason: "`squashPrTitleUsedAsDefault` will be removed.",
          superseded_by: "Use `Repository.squashMergeCommitTitle` instead.",
          owner: "github/pull_requests"
        )
      end
      field :merge_commit_title, Enums::MergeCommitTitle, method: :merge_commit_title_setting, description: "How the default commit title will be generated when merging a pull request.", null: false
      field :merge_commit_message, Enums::MergeCommitMessage, method: :merge_commit_message_setting, description: "How the default commit message will be generated when merging a pull request.", null: false
      field :squash_merge_commit_title, Enums::SquashMergeCommitTitle, method: :squash_merge_commit_title_setting, description: "How the default commit title will be generated when squash merging a pull request.", null: false
      field :squash_merge_commit_message, Enums::SquashMergeCommitMessage, method: :squash_merge_commit_message_setting, description: "How the default commit message will be generated when squash merging a pull request.", null: false

      url_fields prefix: :clone, description: "The URL to clone this repository", visibility: :internal do |repository|
        Loaders::ActiveRecord.load(::User, repository.owner_id).then do |_user|
          Addressable::URI.parse(repository.clone_url)
        end
      end

      field :stars_since, Integer, description: "How many stars the repository has gained in the specified time period.", null: false, required_capabilities: [:mobile_only_schema_mask] do
        argument :period, Enums::TrendingPeriod, "The time period in which to query for new stars.", required: false, default_value: :daily
      end

      def stars_since(**arguments)
        @context[:permission].async_can_list_stargazers?(@object).then do |can_list_stargazers|
          next unless can_list_stargazers

          Stars.domain.repository_stars_since(repository_id: @object.id, period: arguments[:period])
        end
      end

      field :ssh_url, Scalars::GitSSHRemote, description: "The SSH URL to clone this repository", null: false

      def ssh_url
        @object.async_owner.then do |owner|
          owner.async_business.then do
            @object.ssh_url
          end
        end
      end

      field :git_url, Scalars::URI, visibility: :under_development, description: "The Git URL to clone this repository", null: false

      def git_url
        @object.async_owner.then do |_user|
          Addressable::URI.parse(@object.gitweb_url)
        end
      end

      url_fields prefix: :svn, description: "The SVN URL to clone this repository", visibility: :internal do |repository|
        repository.async_owner.then do |_user|
          Addressable::URI.parse(repository.svn_url)
        end
      end

      field :viewer_can_toggle_wiki, Boolean, visibility: :under_development, description: "If the viewer has permissions to toggle the wiki", null: false

      def viewer_can_toggle_wiki
        @object.async_can_toggle_wiki?(context[:viewer])
      end

      field :viewer_can_toggle_projects, Boolean, visibility: :under_development, description: "If the viewer has permissions to toggle the Projects feature on this repository", null: false

      def viewer_can_toggle_projects
        @object.async_can_toggle_projects?(context[:viewer])
      end

      field :can_enable_projects, Boolean, visibility: :under_development, description: "If Projects can be enabled for this repository", null: false, method: :async_can_enable_projects?

      field :viewer_can_toggle_page_settings, Boolean, visibility: :internal, description: "If the viewer has permissions to toggle the page settings", null: false

      def viewer_can_toggle_page_settings
        @object.async_can_toggle_page_settings?(context[:viewer])
      end

      field :viewer_can_set_interaction_limits, Boolean, visibility: :under_development, description: "If the viewer has permissions to set interaction limits on this repository", null: false

      def viewer_can_set_interaction_limits
        @object.async_can_set_interaction_limits?(context[:viewer])
      end

      field :viewer_can_manage_webhooks, Boolean, visibility: :under_development, description: "If the viewer has permissions to manage webhooks on this repository", null: false

      def viewer_can_manage_webhooks
        @object.async_can_manage_webhooks?(context[:viewer])
      end

      field :viewer_can_manage_deploy_keys, Boolean, visibility: :under_development, description: "If the viewer has permissions to manage deploy keys for this repository", null: false

      def viewer_can_manage_deploy_keys
        @object.async_can_manage_deploy_keys?(context[:viewer])
      end

      field :repo_type_icon, String, visibility: :internal, description: "The name of the octicon to use for this repository", null: false

      def repo_type_icon
        @object.async_mirror.then do |_mirror|
          @object.repo_type_icon
        end
      end

      field :viewer_can_toggle_merge_types, Boolean, visibility: :internal, description: "If the viewer has permissions to toggle the merge settings", null: false

      def viewer_can_toggle_merge_types
        @object.async_can_toggle_merge_settings?(context[:viewer])
      end

      field :viewer_can_set_social_preview, Boolean, visibility: :internal, description: "If the viewer has permissions to set the Social preview", null: false

      def viewer_can_set_social_preview
        @object.async_can_set_social_preview?(context[:viewer])
      end

      # NOTE: This field should never be made public. The information it provides is accessible
      #  via the Commit's history connection. Currently that connection is uncached however,
      #  so until we add caching to list_revision_history_multiple we need to use this method
      #  instead as the additional traffic would be rather high.
      field :latest_commit, Objects::Commit, visibility: :internal, description: "The latest commit for the given path on the given ref.", null: true do
        argument :path, String, "The path to search for the latest commit. Defaults to the root.", required: false
        argument :ref_name, String, "The ref to search for the latest commit. Defaults to the default branch for the repository.", required: false
      end

      def latest_commit(ref_name: nil, path: nil)
        @object.async_last_touched(ref_name, path)
      end

      def self.load_from_next_global_id(parsed_id)
        Loaders::ActiveRecord.load(::Repository, parsed_id.parts[:id], security_violation_behaviour: :nil)
      end

      def self.load_from_global_id(id)
        Loaders::ActiveRecord.load(::Repository, id.to_i, security_violation_behaviour: :nil)
      end

      def self.load_from_params(params)
        Objects::User.load_from_params(user_id: params[:user_id]).then do |user|
          user && user.find_repo_by_name(params[:repository])
        end
      end

      field :organization, Objects::Organization, visibility: :under_development, description: "The organization this repository belongs to.", null: true, method: :async_organization

      field :organization_database_id, Integer, visibility: :internal, description: "The database id of the organization this repository belongs to.", null: true, method: :organization_id

      field :organization_discussion, Boolean, visibility: :internal, description: "If the repository is an organization discussion target", null: true

      def organization_discussion
        @object.async_organization_discussion.then do |organization_discussion|
          organization_discussion.present?
        end
      end

      field :temp_clone_token, String, minimum_accepted_scopes: ["public_repo"], description: "Temporary authentication token for cloning this repository.", null: true

      def temp_clone_token
        @context[:permission].async_can_get_repo_temp_clone_token?(@object).then do |can_get_repo_temp_clone_token|
          if can_get_repo_temp_clone_token && (current_viewer = @context[:viewer]) # @context[:viewer] can't be nil
            @object.temp_clone_token(current_viewer)
          else
            nil
          end
        end
      end

      field :used_by_enabled, Boolean, description: "Is the Used By button displayed on the repository", null: true, visibility: :internal

      def used_by_enabled
        @object.async_configuration_owners.then do
          @object.used_by_enabled?
        end
      end

      field :actions_filter_diff, ActionsFilterDiff, description: "Diff required for actions path filtering", null: true, visibility: :internal do
        argument :head_sha, Scalars::GitObjectID, "The head sha for the comparison", required: true
        argument :base_sha, Scalars::GitObjectID, "The base sha for the comparison", required: true
        argument :ref, String, "The full ref of the head, e.g refs/heads/topic-branch", required: false
        argument :pull_request, ID, "The PR related to the compare", required: false
      end

      def actions_filter_diff(**args)
        ActionsFilterDiff.generate_async(@object, **args)
      end

      field :used_by_package_id, String, description: "Dependency Graph Package ID specified by user for display in Used By button", null: true, visibility: :internal

      def used_by_package_id
        @object.async_configuration_owners.then do
          @object.used_by_package_id
        end
      end

      field :abuse_reported_to_maintainer, Connections.define(Objects::AbuseReport), description: "The abuse reports made to the maintainers of this repository.", connection: true, null: false do
        argument :order_by, Inputs::AbuseReportOrder, "Ordering options for abuse reports returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
        argument :filter, Enums::AbuseReportFilter, "Filter abuse reports by whether they've been marked as resolved.", required: false,
          default_value: "all"
      end

      def abuse_reported_to_maintainer(order_by:, filter:)
        scope = ::AbuseReport.for_repository_maintainer(@object.id)

        if filter == "resolved"
          scope = scope.where(resolved: true)
        elsif filter == "unresolved"
          scope = scope.where(resolved: false)
        end

        table = T.unsafe(scope).table_name

        scope = scope.order("#{table}.#{order_by[:field]} #{order_by[:direction]}")
        scope
      end

      field :commit_is_in_branch_or_tag, Boolean, visibility: :internal, description: "Whether the commit is reachable in this repository.", null: true do
        argument :oid, Scalars::GitObjectID, "The commit's Git object ID", required: true
      end

      def commit_is_in_branch_or_tag(**arguments)
        @object.is_commit_in_branch_or_tag?(arguments[:oid])
      end

      field :commit_is_from_merge_queue, Boolean, visibility: :internal, description: "Whether the commit is from the default merge queue in this repository.", null: true do
        argument :oid, Scalars::GitObjectID, "The commit's Git object ID", required: true
      end

      def commit_is_from_merge_queue(**arguments)
        @object.async_default_branch.then do |default_branch_name|
          # TODO: This should be async as well.
          if queue = @object.merge_queue_for(branch: default_branch_name)
            head_shas = queue.entries.pluck(:head_sha)
            head_shas.compact.include?(arguments[:oid])
          else
            false
          end
        end
      end

      field :funding_links, [Objects::FundingLink],
        description: "The funding links for this repository",
        null: false

      def funding_links
        @object.async_has_funding_file?.then do |has_funding|
          next [] unless has_funding
          results = []

          @object.funding_links.validated_config.each do |key, value|
            platform = ::FundingPlatforms::ALL[key.to_sym]

            Array(value).each do |url|
              results << Platform::Models::FundingLink.new(
                repository: @object,
                platform: platform.key,
                url: "#{platform.url}#{url}",
              )
            end
          end

          results
        end
      end

      field :is_user_configuration_repository, Boolean,
        description: "Is this repository a user configuration repository?",
        null: false,
        method: :async_user_configuration_repository?

      field :issue_templates, [IssueTemplate], description: "Returns a list of issue templates associated to the repository", null: true

      def issue_templates
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          templates.valid_templates.select { |template| !template.structured? }.map do |template|
            template.current_repository = @object
            template
          end
        end
      end

      field :has_any_templates, Boolean, description: "Returns true if the repository has any issue templates", null: false, visibility: :internal

      def has_any_templates
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          templates.any?
        end
      end

      field :issue_template, IssueTemplate, description: "Returns an issue template that matches the given filename, or nil if it doesn't exist, associated with the repository ", null: true,  visibility: :internal do
        argument :filename, String, "Filter the list by a given issue template file name", required: true,  visibility: :internal
      end

      def issue_template(**arguments)
        @object.async_preferred_issue_templates(@context[:viewer], {
            filename: utf8(arguments[:filename]),
            is_form: false,
          }).then do |templates|
          results = templates.valid_templates.select { |template| !template.structured? }.map do |template|
            template.current_repository = @object
            template
          end
          results.size == 1 ? results.first : nil
        end
      end

      field :issue_forms, [IssueForm], visibility: :under_development, description: "Returns a list of issue forms associated to the repository", null: true

      def issue_forms
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          templates.valid_yaml_templates.select { |template| template.structured? }.map do |template|
            template.current_repository = @object
            template
          end
        end
      end

      field :issue_form, IssueForm, visibility: :internal, description: "Returns an issue form that matches the given filename, or nil if it doesn't exist, associated with the repository", null: true do
        argument :filename, String, "Filter the list by a given issue form file name", required: true,  visibility: :internal
      end

      def issue_form(**arguments)
        @object.async_preferred_issue_templates(@context[:viewer], {
          filename: utf8(arguments[:filename]),
          is_form: true,
        }).then do |templates|
          results = templates.valid_yaml_templates.select { |template| template.structured? }.map do |template|
            template.current_repository = @object
            template
          end
          results.size == 1 ? results.first : nil
        end
      end


      field :template_tree_url, Scalars::URI, visibility: :under_development, description: "Returns the URL to the template tree for the repository", null: false

      def template_tree_url
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          "#{GitHub.url}#{templates.repository.template_tree_path}"
        end
      end

      field :pull_request_templates, [PullRequestTemplate], description: "Returns a list of pull request templates associated to the repository", null: true, method: :async_pull_request_templates

      field :contact_links, [RepositoryContactLink], description: "Returns a list of contact links associated to the repository", null: true

      def contact_links
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          config = templates.issue_template_config
          config.contact_links
        end
      end

      field :issue_form_links, [RepositoryContactLink], required_capabilities: [:mobile_only_schema_mask], description: "Returns a list of issue form links associated to the repository", null: true

      def issue_form_links
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          config = templates.issue_template_config
          config.contact_links(issue_forms_only: true)
        end
      end

      field :is_blank_issues_enabled, Boolean, description: "Returns true if blank issue creation is allowed", null: false

      def is_blank_issues_enabled
        @object.async_preferred_issue_templates(@context[:viewer]).then do |templates|
          config = templates.issue_template_config
          config.blank_issues_enabled?
        end
      end

      field :is_security_policy_enabled, Boolean, description: "Returns true if this repository has a security policy", null: true

      def is_security_policy_enabled
        @object.security_policy.exists?
      end

      field :security_policy_url, Scalars::URI, description: "The security policy URL.", null: true

      def security_policy_url
        return unless @object.security_policy.exists?

        "#{@object.permalink}/security/policy"
      end

      field :contributing_file_url, Scalars::URI, description: "The contributing file URL.", visibility: :internal, null: true
      def contributing_file_url
        relative_path = preferred_file_path(type: :contributing, repository: @object)
        return URI.join(GitHub.url, relative_path) if relative_path
        nil
      end

      field :code_of_conduct_file_url, Scalars::URI, description: "The code of conduct file URL.", visibility: :internal, null: true
      def code_of_conduct_file_url
        relative_path = preferred_file_path(type: :code_of_conduct, repository: @object)
        return URI.join(GitHub.url, relative_path) if relative_path
        nil
      end

      field :submodules, Connections.define(Objects::Submodule), description: "Returns a list of all submodules in this repository parsed from the .gitmodules file as of the default branch's HEAD commit.", null: false, connection: true

      def submodules
        @object.async_default_branch_ref.then do |ref|
          if !ref
            # async_default_branch_ref returned nil, just return an empty array.
            ArrayWrapper.new([])
          else
            @object.async_submodules(ref.target_oid).then do |submodules|
              ArrayWrapper.new(submodules.values)
            end
          end
        end
      end

      # Actions OIDC sub claim customization template
      field :oidc_sub_claim_customization_template, String, null: true, visibility: :internal, description: "Returns the OIDC sub claim customization template for the organization, or nil if none exists."

      def oidc_sub_claim_customization_template
        # `@object` is the Repository object
        context[:permission].async_owner_if_org(@object).then do |org|
          configuration = RepositoryActionsOIDCConfig.get_configurations(@object.id)

          # if configuration is empty or subject customization is not enabled, return true. Since we don't want the repo to opt in to subject customization by default.
          return nil if !configuration.present? || configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_DISABLED].present?

          # return the template set for the repository.
          if configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE].present?
            return configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE]
          # return the template set for the organization. When a user account is the repository owner, this is not the case.
          elsif !org.nil?
            template_entity = OrganizationOIDCSubClaimTemplate.get_template_for_org(org.id)
            return template_entity.nil? ? nil : template_entity.template
          else
            return nil
          end
        end
      end

      field :actions_cache_size_limit, Integer, null: false, visibility: :internal, description: "Returns the actions cache size limit in GBs for the repository"

      def actions_cache_size_limit
        @object.actions_cache_size_limit
      end

      # Actions OIDC enterprise issuer url customization selection
      field :customize_enterprise_oidc_issuer, Boolean, null: false, visibility: :internal, description: "Enterprise admin selection for customising the OIDC issuer URL"

      def customize_enterprise_oidc_issuer
        # `@object` is the Repository object
        context[:permission].async_owner_if_org(@object).then do |org|
          return false if org.nil?
          org.async_business.then do |business|
            return false if business.nil?
            entity = EnterpriseOIDCIssuerUrlCustomisation.get_issuer_policy(business.id)
            entity.nil? ? false : entity.include_enterprise_name
          end
        end
      end

      field :actions_retention_limit, Integer, null: false, visibility: :internal, description: "Returns the retention limit in days for the actions artifacts and logs in the repository"

      def actions_retention_limit
        @object.actions_retention_limit
      end

      field :repo_self_hosted_runners_disabled, Boolean, null: false, visibility: :internal, description: "Returns whether self-hosted runners are enabled for the repository"

      def repo_self_hosted_runners_disabled
        @object.repo_self_hosted_runners_disabled_by_owner?
      end

      field :can_use_environments, Boolean, null: false, visibility: :internal, description: "Returns whether this repository can use environment features"

      def can_use_environments
        @object.async_owner.then do |_owner|
          @object.can_use_environments?
        end
      end

      field :environment, Objects::Environment, null: true do
        description "Returns a single active environment from the current repository by name."
        argument :name, String, "The name of the environment to be returned.", required: true
      end

      def environment(name:)
        not_found_message = "Could not resolve to an Environment with the name #{name}."

        unless @object.can_use_environments? || @context[:permission].target == :internal
          raise Errors::NotFound, not_found_message
        end

        Loaders::EnvironmentByName.load(@object.id, name).then do |environment|
          if environment.nil?
            raise Errors::NotFound, not_found_message
          end

          @context[:permission].typed_can_see?("Environment", environment).then do |readable|
            if readable
              environment
            else
              raise Errors::NotFound, not_found_message
            end
          end
        end
      end

      field :environments, Connections.define(Objects::Environment), description: "A list of environments that are in this repository.", null: false, connection: true do
        argument :order_by, Inputs::Environments, "Ordering options for the environments", required: false, default_value: { field: "name", direction: "ASC" }
        argument :pinned_environment_filter, Platform::Enums::EnvironmentPinnedFilterField, "Filter to control pinned environments return", required: false, default_value: "all", visibility: :public
        argument :names, [String], "The names of the environments to be returned.", required: false, default_value: []
      end

      def environments(order_by: { field: "name", direction: "ASC" }, names: [], pinned_environment_filter: "all")
        # The OR `can_see_deployments?` condition should be a temporary workaround until we can
        # fix the `can_use_environments?` check with a more thorough permissions audit for Environments.
        return ::Environment.none unless @object.can_use_environments? || @object.can_see_deployments?(context[:viewer])

        context[:permission].async_owner_if_org(@object).then do |org|
          if context[:permission].access_allowed?(:read_actions, repo: @object, resource: @object, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
            scope = @object.environments
            if pinned_environment_filter == "only"
              scope = scope.joins(:pinned_environment)
            elsif pinned_environment_filter == "none"
              scope = scope.left_joins(:pinned_environment).where(pinned_environment: { id: nil })
            end
            if names.present?
              scope = scope.where(name: names)
            end
            scope.order(order_by[:field] => order_by[:direction])
          else # Not permitted to list environments
            ::Environment.none
          end
        end
      end

      field :forking_allowed, Boolean, null: false, description: "Whether this repository allows forks."

      def forking_allowed
        GitHub::PrefillAssociations.prefill_associations(@object, :group_map)
        @object.async_organization.then do
          @object.allows_forking?
        end
      end

      field :lists, Connections.define(Objects::UserList), description: "A list of user-lists to which this repository belongs", required_capabilities: [:mobile_only_schema_mask], null: false, connection: true do
        argument :order_by, Inputs::UserListOrder, "Ordering options for the returned lists", required: false, default_value: { field: "last_added_at", direction: "DESC" }
        argument :only_owned_by_viewer, Boolean, "Only show lists owned by the current viewer, overrides ownerId", default_value: false, required: false
        argument :owner_id, ID, "Only show lists that belong to this user ID, ignored if onlyOwnedByViewer is true", default_value: nil, required: false
      end

      def lists(order_by:, only_owned_by_viewer:, owner_id:)
        order_value = { order_by[:field] => order_by[:direction] }

        if only_owned_by_viewer
          ::UserList.owned_by(context[:viewer]).with_item(object).order(order_value)
        elsif owner_id.present?
          Helpers::NodeIdentification.async_typed_object_from_id([Objects::User], owner_id, context).then do |owner|
            lists = (context[:viewer] == owner) ? ::UserList.scoped : ::UserList.public_scope
            lists.owned_by(owner).with_item(object).order(order_value)
          end
        else
          lists = ::UserList.public_scope
          lists = lists.or(::UserList.private_scope.owned_by(context[:viewer]))
          lists.with_item(object).order(order_value)
        end
      end

      field :codeowners, Objects::RepositoryCodeowners, description: "Information extracted from the repository's `CODEOWNERS` file.", null: true do
        argument :ref_name, String, "The ref name used to return the associated `CODEOWNERS` file.", required: false
      end

      def codeowners(ref_name: nil)
        @object.async_default_branch.then do |default_branch_name|
          codeowners = ::Repository::Codeowners.new(@object, ref: ref_name || default_branch_name)

          if codeowners.file.present?
            codeowners
          else
            nil
          end
        end
      end

      field :codeql_databases, Connections::CodeqlDatabase, description: "A list of CodeQL databases uploaded for this repository", null: true, visibility: :internal, connection: true do
        argument :order_by, Inputs::CodeqlDatabaseOrder, "Ordering options for CodeQL databases returned.", required: false, default_value: { field: "created_at", direction: "DESC" }
      end
      def codeql_databases(order_by:)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          return nil
        end

        query = ::CodeqlDatabase.where(repository_id: @object.id)
        if order_by[:field] == "created_at"
          query = query.order(created_at: order_by[:direction])
        elsif order_by[:field] == "size"
          query = query.order(size: order_by[:direction])
        end
        query
      end

      field :project_next, Objects::ProjectNext,
        minimum_accepted_scopes: ["read:org", "repo"],
        description: "Finds and returns the Project according to the provided Project number.",
        required_capabilities: [:mobile_only_schema_mask],
        null: true do
          argument :number, Integer, "The ProjectNext number.", required: true
        end

      def project_next(**arguments)
        Loaders::ProjectNextByNumber.load(@object, @context[:viewer], arguments[:number])
      end

      field :projects_next, Connections.define(Objects::ProjectNext),
        minimum_accepted_scopes: ["read:org", "repo"],
        description: "List of projects linked to this repository.",
        required_capabilities: [:mobile_only_schema_mask],
        numeric_pagination_enabled: true,
        null: false do
          argument :query, String, "A project to search for linked to the repo.", required: false
          argument :sort_by, Enums::ProjectNextOrderField,
            "How to order the returned project objects.", required: false, default_value: "title"
        end

      def projects_next(**arguments)
        Loaders::ProjectNextByQuery.load(
          @object,
          @context[:viewer],
          arguments[:query] || ""
        ).then { |projects| sort_projects_next(projects, arguments) }
      end

      def sort_projects_next(projects, arguments)
        ArrayWrapper.new(projects.compact&.sort_by { |p| p.send(arguments[:sort_by].to_sym) || "" })
      end

      field :project_v2, Objects::ProjectV2,
        minimum_accepted_scopes: ["read:project"],
        description: "Finds and returns the Project according to the provided Project number.",
        null: true do
          argument :number, Integer, "The Project number.", required: true
        end

      def project_v2(number:)
        Loaders::ProjectV2ByNumber.load(@object, @context[:viewer], number).then do |project|
          Helpers::ProjectV2.async_validate_project_by_number(project, number, @context[:permission])
        end
      end

      field :projects_v2, Connections.define(Objects::ProjectV2),
        minimum_accepted_scopes: ["read:project"],
        description: "List of projects linked to this repository.",
        numeric_pagination_enabled: true,
        null: false do
          argument :query, String, "A project to search for linked to the repo.", required: false
          argument :use_full_term_query,
            Boolean,
            "Search project titles that match the entire query string",
            required: false,
            default_value: false,
            visibility: :internal

          argument :order_by,
            Inputs::ProjectV2Order,
            "How to order the returned projects.",
            required: false,
            default_value: { field: "number", direction: "DESC" }

          argument :min_permission_level,
            Enums::ProjectV2PermissionLevel,
            "Filter projects based on user role.",
            required: false,
            default_value: "read"
        end

      def projects_v2(**arguments)
        Loaders::ProjectV2ByQuery.load(
          @object,
          @context[:viewer],
          arguments[:query] || "",
          arguments[:min_permission_level],
          arguments[:use_full_term_query] || false
        ).then { |projects| sort_projects_v2(projects, arguments[:order_by], arguments[:query], @context[:viewer]) }
      end

      field :workflows, Connections.define(Objects::Workflow),
        description: "List of workflows associated with this repository.",
        null: false,
        required_capabilities: [:mobile_only_schema_mask] do
        argument :order_by, Inputs::WorkflowOrder,
          "Ordering options for workflows returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def workflows(order_by:)
        viewer = @context[:viewer]
        workflows = @object.workflows.not_deleted

        if viewer&.spammy?
          workflows = workflows.spammer_viewable_workflows(viewer&.id)
        elsif !viewer&.site_admin?
          workflows = workflows.viewable_workflows
        end

        if order_by
          workflows = workflows.order(order_by[:field] => order_by[:direction])
        end

        workflows
      end

      field :web_commit_signoff_required, Boolean, null: false, description: "Whether contributors are required to sign off on web-based commits in this repository."

      def web_commit_signoff_required
        @object.async_configuration_owners.then do
          @object.dco_signoff_enabled?
        end
      end

      field :is_writable, Boolean, null: false, visibility: :internal, description: "Whether the repository can be updated based on whether it is locked, being migrated, or access disabled."

      def is_writable
        @object.async_writable?
      end

      field :slash_commands_enabled, Boolean, null: false, visibility: :internal, description: "Whether slash commands are enabled for this repository."

      def slash_commands_enabled
        viewer = @context[:viewer]
        SlashCommands.enabled_for?(viewer, @object)
      end

      field :issue_types, Connections.define(Objects::IssueType), "A list of the repository's issue types", connection: true, null: true do
        argument :order_by, Inputs::IssueTypeOrder, description: "Ordering options for issue types returned from the connection.", required: false, default_value: { field: "created_at", direction: "ASC" }
      end

      def issue_types(order_by: nil)
        with_async_database_error_fallback(
          @object.async_owner.then do |owner|
            return nil unless owner.issue_types_enabled?

            owner.async_readable_issue_types_matrix(@context[:viewer]).then do |matrix|
              issue_types = Issues.domain.issue_types.by_organization(owner).filter do |type|
                next false if !@object.private? && type.private?

                type.readable?(matrix)
              end
              Helpers::IssueTypes.order(T.cast(issue_types, T::Array[::IssueType]), order_by)
            end
          end,
          fallback: -> { raise Platform::Errors::ServiceUnavailable, "Issue types are currently unavailable." }
        )
      end

      field :issue_type, resolver: Resolvers::IssueType, description: "Returns a single issue type by name", null: true do
        argument :name, String, "Issue type name.", required: true
      end

      field :contributing_guidelines, ContributingGuidelines, description: "Returns the contributing guidelines for this repository.", null: true

      def contributing_guidelines
        # Check if repo is available and has a contributing guidelines available
        @object.async_disabled_access_reason.then do
          if @object.detect_contributing
            @object.contributing_guidelines
          else
            nil
          end
        end
      end

      field :is_owner_enterprise_managed, Boolean, description: "Returns whether or not the owner of this repository is managed by an enterprise.", null: true, visibility: :internal

      def is_owner_enterprise_managed
        @object.async_owner.then do |owner|
          if owner.class.name == "Organization"
            owner.async_enterprise_managed_user_enabled?
          else
            owner.is_enterprise_managed?
          end
        end
      end

      # TODO: Remove as a part of https://github.com/github/issues/issues/11515 (@Mattamorphic)
      field :is_excluded_from_issue_types, Boolean, description: "Returns whether or not this repository is excluded from using issue types.", null: true do
        visibility :under_development
      end

      def is_excluded_from_issue_types
        false
      end

      field :search, Connections::SearchResultItem, description: "Perform a search across resources, returning a maximum of 1,000 results.", null: false, connection: true, visibility: :internal do
        argument :query, String, "The search string to look for. GitHub search syntax is supported. For more information, see \"[Searching on GitHub](https://docs.github.com/search-github/searching-on-github),\" \"[Understanding the search syntax](https://docs.github.com/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax),\" and \"[Sorting search results](https://docs.github.com/search-github/getting-started-with-searching-on-github/sorting-search-results).\"", required: true
        argument :type, Enums::SearchType, "The types of search items to search within.", required: true
        argument :aggregations, Boolean, "Calculate aggregations. This arg must be true for `languageAggregations` to be returned.", default_value: false, visibility: :internal, required: false
        argument :skip, Integer, "The number of items to skip, for pagination.", required: false, visibility: :internal
      end

      def search(**arguments)
        supported_search_types = %w[Issues IssuesAdvanced Discussions].freeze
        unless supported_search_types.include?(arguments[:type])
          raise Platform::Errors::ArgumentError, "The `type` argument must be one of ISSUE, ISSUE_ADVANCED, DISCUSSION for repo scoped searches. To use the type #{arguments[:type]}, use the global search query instead."
        end
        @context[:scoped_repo_id] = @object.id
        execute_search(**arguments)
      end

      field :announcement_banner, Objects::AnnouncementBanner, description: "The announcement banner set on this repository, if any. Only visible to members of the repository's enterprise.", null: true, feature_flag: :enterprise_banners_repo_level

      def announcement_banner
        EnterpriseBanner.find_by(owner: @object)
      end

      private

      sig { override.returns(T.nilable(::User)) }
      def current_user
        context[:viewer]
      end
    end
  end
end
