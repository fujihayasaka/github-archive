# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class User < Platform::Objects::Base
      include Objects::Base::RecordObjectAccess
      include Helpers::Newsies
      include Helpers::ConditionalAccess
      include Helpers::PrivateProfile
      include Helpers::ProjectV2Sorter
      include Scientist
      include GitHub::ResilienceMixin
      include Platform::Authorization::ReauthorizeScopedObjects

      description "A user is an individual's account on GitHub that owns repositories and can make new content."

      # TODO This needed `allow_nil_for: [:id]` because some Hydro instrumentation
      # tries to build Global IDs for non-persisted objects. Try removing that config,
      # and fix any broken tests to make sure that Hydro instrumentation will still work
      implements_node templates: [[:u, :id]], allow_nil_for: [:id], as: "U", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |user|
        { prefix: :u, id: user.id }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, user)
        permission.access_allowed?(
          :read_user_public,
          resource: Platform::PublicResource.new(resource: user),
          current_repo: nil,
          current_org: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # we are viewing the user here in a public context
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      def self.scope_items(items, context)
        # we want to limit this, for now, to persisted queries
        connection_safe_to_skip_authorization = check_path_for_supported_connection(context.namespace(:interpreter)[:current_path], %w[suggestedAssignees assignees])

        return items.clone if !reauthorize_scoped_objects && connection_safe_to_skip_authorization
        items
      end

      reauthorize_scoped_objects(false)

      scopeless_tokens_as_minimum

      implements Interfaces::Actor
      implements Interfaces::AvatarOwner
      implements Interfaces::PackageOwner
      implements Interfaces::PackageSearch
      implements Interfaces::ProjectOwner
      implements Interfaces::ProjectV2Owner
      implements Interfaces::ProjectV2Recent
      implements Interfaces::RepositoryDiscussionAuthor
      implements Interfaces::RepositoryDiscussionCommentAuthor
      implements Interfaces::RepositoryOwner
      implements Interfaces::MarketplaceListingOwner
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Billable
      implements Interfaces::PlanOwner
      implements Interfaces::FeatureFlaggable
      implements Interfaces::ProfileOwner
      implements Interfaces::Sponsorable
      implements Interfaces::Viewer::Agentic

      FEATURE_FLAG_LIMIT = 25

      database_id_field

      created_at_field
      updated_at_field

      field :login, String, "The username used to login.", null: false, resolver_method: :login_for_api
      def login_for_api
        @object.login_for_api(use: context[:serialize_login])
      end

      url_fields description: "The HTTP URL for this user" do |user|
        template = Addressable::Template.new("/{login}")
        template.expand login: user.display_login
      end

      url_fields prefix: :projects, description: "The HTTP URL listing user's projects" do |user|
        template = Addressable::Template.new("/users/{login}/projects")
        template.expand login: user.display_login
      end

      field :status, Objects::UserStatus,
        description: "The user's description of what they're currently doing.", null: true

      def status
        @object.async_status_visible_to(@context[:viewer])
      end

      field :email, String, minimum_accepted_scopes: ["user:email", "read:user"], description: "The user's publicly visible profile email.", null: false

      def email
        promises = Promise.all([@object.async_profile, @object.async_primary_user_email_role])
        promises.then do |_profile, primary_user_email_role|
          target = primary_user_email_role&.public? ? nil : @object

          accessible = @context[:permission].access_allowed?(
            :v4_get_user_email,
            target: target,
            resource: @object,
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            raise_on_error: false,
          )

          if accessible
            @object.publicly_visible_email(logged_in: !@context[:viewer].nil?) || ""
          else
            ""
          end
        end
      end

      field :is_primary_email_role_public, Boolean, visibility: :internal, description: "Whether the primary email role is public", null: false

      def is_primary_email_role_public
        @object.async_primary_user_email_role.then do |primary_user_email_role|
          !!primary_user_email_role&.public?
        end
      end

      field :primary_email, String, required_capabilities: [:mobile_only_schema_mask], description: "The user's primary email", null: true

      def primary_email
        if @object == context[:viewer]
          @object.async_primary_user_email.then do |primary_email|
            primary_email.email
          end
        else
          nil
        end
      end

      field :possible_profile_emails, [String], visibility: :internal, description: "The user's verified email addresses", null: false

      def self.profile_field(field_name)
        field(field_name, String, null: true, description: "The user's public profile #{field_name}.")
        define_method(field_name) do
          @object.async_profile.then do |profile|
            profile.try(field_name)
          end
        end
      end

      profile_field(:name)
      profile_field(:location)
      profile_field(:bio)
      profile_field(:company)

      field :private_email, String, visibility: :internal, description: "The user's profile email without regard to privacy setting, for internal use only.", null: false

      def private_email
        @object.async_profile.then do |profile|
          profile && profile.email || ""
        end
      end

      field :show_profile_readme, Boolean,
        required_capabilities: [:mobile_only_schema_mask],
        description: "Whether or not a user's profile readme is currently visible",
        null: false,
        method: :async_profile_readme_visible?

      field :configuration_repository, Objects::Repository,
        required_capabilities: [:mobile_only_schema_mask],
        description: "The user's profile configuration repository",
        null: true,
        method: :async_configuration_repository

      field :profile_readme, Objects::RepositoryReadme,
        required_capabilities: [:mobile_only_schema_mask],
        description: "The user's profile readme.",
        null: true

      def profile_readme
        @object.async_profile_readme_visible?.then do |is_visible|
          @object.async_profile_readme if is_visible
        end
      end

      field :no_verified_email, Boolean, visibility: :internal, description: "The user possesses no verified email address", null: false

      def no_verified_email
        ::UserEmail.where(user_id: @object.id).verified.none?
      end

      field :bio_html, Scalars::HTML,
        description: "The user's public profile bio as HTML.",
        method: :async_profile_bio_html,
        null: false

      field :company_html, Scalars::HTML,
        description: "The user's public profile company as HTML.",
        method: :async_profile_company_html,
        null: false

      field :website_url, Scalars::URI, description: "A URL pointing to the user's public website/blog.", null: true

      def website_url
        @object.async_profile.then do |profile|
          profile.try(:blog)
        end
      end

      field :orcid_record, Objects::OrcidRecord, description: "An academic researcher's ORCID record.", null: true,
        required_capabilities: [:mobile_only_schema_mask]

      def orcid_record
        @object.async_user_settings_record.then do |settings|
          next nil if settings && !settings.get(:display_orcid_id_on_profile)

          @object.async_orcid_record
        end
      end

      field :twitter_username, String, description: "The user's Twitter username.", null: true

      def twitter_username
        @object.async_profile.then do |profile|
          profile.try(:twitter_username)
        end
      end

      field :twitter_url, Scalars::URI, description: "A URL pointing to the user's Twitter profile", null: true, visibility: :internal

      def twitter_url
        @object.async_profile.then do |profile|
          profile.try(:twitter_url)
        end
      end

      field :social_accounts, Connections.define(Objects::SocialAccount), null: false,
        description: "The user's social media accounts, ordered as they appear on the user's profile."

      def social_accounts
        @object.async_profile.then do |profile|
          ArrayWrapper.new(Array(profile&.social_accounts))
        end
      end

      field :pronouns, String, description: "The user's profile pronouns", null: true

      def pronouns
        return if @object.private_profile_for?(@context[:viewer])

        @object.async_profile.then do |profile|
          profile&.pronouns
        end
      end

      field :has_ever_contributed, Boolean, null: false, visibility: :internal,
        description: "Determine if the user has ever created a repository, made a commit " \
                     "contribution, opened an issue, opened a pull request, or left a pull " \
                     "request review.", method: :any_contributions_ever?

      field :avatar_url, Scalars::URI, description: "A URL pointing to the user's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(**arguments)
        preload_promise =
          # TODO we need to remove this condition. The `Bot` object should be responsible
          # for the avatarUrl of bot records. If a ::Bot somehow is being resolved into
          # here, then the field that marshaled it needs to be updated (perhaps to Actor)
          if @object.is_a?(::Bot)
            # async integration may resolve to nil
            @object.async_integration.then do |integration|
              if integration
                integration.async_owner
              else
                Promise.resolve(nil)
              end
            end
          else
            Promise.resolve(nil)
          end

        if GitHub.private_mode_enabled? && !GitHub.multi_tenant_enterprise? && Apps::Privileged.capable?(:enterprise_avatar_display, app: context[:oauth_app])
          "#{GitHub.api_url}/enterprise/avatars#{@object.primary_avatar_path}?s=#{arguments[:size]}"
        else
          preload_promise.then do
            @object.async_primary_avatar.then do
              @object.primary_avatar_url(arguments[:size])
            end
          end
        end
      end

      field :is_hireable, Boolean, description: "Whether or not the user has marked themselves as for hire.", null: false

      def is_hireable
        private_profile_boolean do
          @object.async_profile.then do |profile|
            !!(profile && profile.hireable?)
          end
        end
      end

      field :display_staff_badge, Boolean, visibility: :internal, description: "Whether or not staff have marked to display staff badge.", null: false

      def display_staff_badge
        @object.async_profile.then do |profile|
          profile.try(:display_staff_badge?) || false
        end
      end

      field :show_staff_badge_on_profile, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether or not the staff badge should be displayed on profile and hovercard.", null: false

      def show_staff_badge_on_profile
        Promise.all([
          @object.async_profile,
          @object.async_user_metadata,
        ]).then do |_profile, _metadata|
          !!@object.show_staff_badge_to?(context[:viewer])
        end
      end

      field :show_pro_plan_badge_on_profile, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether or not the pro badge should be displayed on profile and hovercard.", null: false, method: :has_pro_plan_badge?

      field :can_have_pro_badge, Boolean, visibility: :internal, description: "Whether or not the user can display a pro badge on their profile.", null: false, method: :can_have_pro_badge?

      field :is_pro_plan, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether or not the user has an active pro plan.", null: true

      def is_pro_plan
        if is_viewer
          @object.plan.pro?
        else
          nil
        end
      end

      field :is_enterprise_managed_user, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether or not the user is an Enterprise Managed User (EMU). Returns a value only if the user is the viewer.", null: true

      def is_enterprise_managed_user
        if is_viewer
          @object.is_enterprise_managed?
        else
          nil
        end
      end

      field :copilot_license_type,
        Platform::Enums::CopilotLicenseType,
        description: "The user's license type for Copilot",
        required_capabilities: [:access_copilot_limited_graphql_api],
        null: true

      def copilot_license_type
        return unless is_viewer
        copilot_user = Copilot::User.new(object)
        copilot_user.async_customer.then do
          if copilot_user.has_cfb_access?
            # this means they have Business or Enterprise
            next "copilot_enterprise" if copilot_user.copilot_plan_enterprise?
            "copilot_business"
          else
            next "copilot_free" if copilot_user.has_limited_access?
            next "copilot_individual_pro_plus" if copilot_user.has_pro_plus_access?
            next "copilot_individual_max" if copilot_user.has_max_access?
            next "copilot_individual" if copilot_user.has_cfi_access?
            "no_access"
          end
        end
      end

      field :copilot_subscription_platform,
        Enums::CopilotSubscriptionPlatform,
        description: "The platform that the user manages their paid Copilot subscription from, null if not subscribed.",
        null: true,
        required_capabilities: [:mobile_only_schema_mask]

      def copilot_subscription_platform
        return unless is_viewer

        copilot_user = Copilot::User.new(object)
        copilot_user.async_customer.then do
          context[:viewer].async_plan_subscription.then do
            # No Copilot access
            next unless copilot_user.has_copilot_access?

            # Copilot Limited subscription
            next if copilot_user.has_limited_access?

            # Copilot Business or Enterprise subscription
            next "managed" if copilot_user.has_cfb_access? || copilot_user.has_cfe_access?

            # Copilot Free subscription
            # Note: This is the free version of CfI offered to users such as OSS maintainers and students
            #       We return "web" because registration for this SKU is not supported via Mobile.
            next "web" if copilot_user.has_free_access?

            # Individual subscription
            if copilot_user.has_cfi_access? || copilot_user.has_pro_plus_access? || copilot_user.has_max_access?
              copilot_user.async_copilot_active_subscription_item.then do |item|
                next "apple" if item.apple_in_app_purchase?
                next "google" if item.google_in_app_purchase?
                next "web"
              end
            else
              next "unknown"
            end
          end
        end
      end

      field :copilot_limited_user,
        Objects::CopilotLimitedUser,
        description: "Properties of the current Copilot user, if limited by Copilot Free.",
        null: true,
        required_capabilities: [:access_copilot_limited_graphql_api]

      def copilot_limited_user
        return unless is_viewer
        Copilot::LimitedUser.for_subscribed_user(object)
      end

      field :copilot_consumptive_user,
        Objects::CopilotConsumptiveUser,
        description: "Properties of the current Copilot consumptive user.",
        null: true,
        required_capabilities: [:access_copilot_consumptive_graphql_api]

      def copilot_consumptive_user
        return unless is_viewer
        Copilot::Public::User.new(object)
      end

      field :feature_flags,
      [FeatureFlagState],
      description: "Feature flag states for the viewer",
      required_capabilities: [:mobile_only_schema_mask],
      null: true do
        argument :flags, [String], "The feature flags to be queried", required: true
      end

      def feature_flags(**arguments)
        return unless is_viewer

        if arguments[:flags].length > FEATURE_FLAG_LIMIT
          raise Platform::Errors::ArgumentError, "flags limit is #{FEATURE_FLAG_LIMIT}"
        end

        argument_symbols = arguments[:flags].map { |flag| flag.to_sym }

        valid_flags = argument_symbols & Mobile::ClientPublicApiFeatureFlags::FLAGS

        ::FeatureFlag.vexi.preload(valid_flags, instrumentation_properties: {
          "code.namespace": self.class.name&.underscore,
        })

        argument_symbols.map do |flag|
          if valid_flags.include?(flag)
            enabled = context[:viewer].feature_flag_enabled_or_raise?(flag) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            Models::FeatureFlagState.new(flag, enabled)
          else
            Models::FeatureFlagState.new(flag, false)
          end
        end
      end

      field :copilot_endpoints,
        Platform::Objects::CopilotEndpoints,
        description: "The user's Copilot endpoint information",
        null: true

      def copilot_endpoints
        return unless is_viewer

        if object.feature_flag_enabled?(:copilot_sku_isolation_use_public_user_perf, default: false)
          Copilot::SKUIsolation.for_user(object)
        else
          Copilot::SKUIsolation.new(
            Copilot::User.new(object),
            GitHub::CurrentTenant.get,
          )
        end
      end

      field :available_copilot_upgrade_skus,
        [Enums::CopilotLicenseType],
        description: "Copilot SKUs that the user is eligible for upgrades to.",
        null: true,
        required_capabilities: [:mobile_only_schema_mask]

      def available_copilot_upgrade_skus
        return unless is_viewer
        return if context[:viewer].spammy?
        return if context[:viewer].has_any_trade_restrictions?

        return [] if object.is_enterprise_managed?

        copilot_user = Copilot::User.new(object)

        if copilot_user.feature_flag_enabled?(:copilot_iap_max_sku, default: false)
          copilot_user.async_customer.then do
            # CFB/CFE users cannot upgrade to CFI plans
            next [] if copilot_user.has_cfb_access? || copilot_user.has_cfe_access?

            # Max users cannot upgrade beyond CFI Max at the moment
            next [] if copilot_user.has_max_access?

            if copilot_user.has_cfi_pro_plus_access?
              next %w(copilot_individual_max)
            # If the user has CFI access on a non-Copilot Free plan, they're also eligible for CFI Pro+/Max
            elsif copilot_user.has_cfi_access? && !copilot_user.has_limited_access?
              next %w(copilot_individual_pro_plus copilot_individual_max)
            else
              @object.async_plan_subscription.then do
                next [] unless !copilot_user.administrative_blocked? && copilot_user.can_subscribe_to_cfi?

                context[:viewer].async_trade_screening_record.then do
                  next context[:viewer].has_commercial_interaction_restriction? ? [] : %w(copilot_individual copilot_individual_pro_plus copilot_individual_max)
                end
              end
            end
          end
        else
          copilot_user.async_customer.then do
            # CFB/CFE users cannot upgrade to CFI plans
            next [] if copilot_user.has_cfb_access? || copilot_user.has_cfe_access?

            # Pro+ users cannot upgrade beyond CFI Pro+ at the moment
            next [] if copilot_user.has_pro_plus_access?

            # If the user is eligible for CFI and they are NOT on a Copilot Free plan, they're also eligible for CFI Pro+
            if copilot_user.has_cfi_access? && !copilot_user.has_limited_access?
              next %w(copilot_individual_pro_plus)
            else
              @object.async_plan_subscription.then do
                next [] unless !copilot_user.administrative_blocked? && copilot_user.can_subscribe_to_cfi?

                context[:viewer].async_trade_screening_record.then do
                  next context[:viewer].has_commercial_interaction_restriction? ? [] : %w(copilot_individual copilot_individual_pro_plus)
                end
              end
            end
          end
        end
      end

      field :viewer_in_app_purchases,
        Objects::InAppPurchases,
        description: "In-app purchase information made by the viewer.",
        required_capabilities: [:mobile_only_schema_mask],
        null: true

      def viewer_in_app_purchases
        return unless is_viewer

        Models::InAppPurchases.new(object)
      end

      field :viewer_can_subscribe_to_copilot_limited,
        Boolean,
        description: "Whether the viewer can subscribe to Copilot Individual Free (e.g., limited user).",
        required_capabilities: [:access_copilot_limited_graphql_api],
        null: false

      def viewer_can_subscribe_to_copilot_limited
        return false unless is_viewer
        return false if context[:viewer].spammy?
        return false unless context[:viewer].feature_flag_enabled_or_raise?(:copilot_free_mobile) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if context[:viewer].has_any_trade_restrictions?
        return false if @object.is_enterprise_managed?

        copilot_user = Copilot::User.new(object)

        @object.async_plan_subscription.then do
          copilot_user.can_signup_for_limited?
        end
      end

      field :viewer_can_subscribe_to_copilot_individual,
        Boolean,
        description: "Whether the viewer can subscribe to Copilot Individual. Returns false for a user, who is eligible for free licenses",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def viewer_can_subscribe_to_copilot_individual
        return false unless is_viewer
        return false unless GitHub.iap_enabled?
        return false if context[:viewer].spammy?
        return false if context[:viewer].has_any_trade_restrictions?
        return false if @object.is_enterprise_managed?

        copilot_user = Copilot::User.new(object)

        copilot_user.async_customer.then do
          next false if copilot_user.administrative_blocked?
          next false if !copilot_user.can_subscribe_to_cfi?
          next false if copilot_user.can_signup_for_free?

          context[:viewer].async_trade_screening_record.then do |_|
            !context[:viewer].has_commercial_interaction_restriction?
          end
        end
      end

      field :is_copilot_dotcom_chat_enabled, Boolean, visibility: :internal, description: "Whether Copilot Chat for Dotcom is enabled for this user", null: false

      def is_copilot_dotcom_chat_enabled
        return false unless is_viewer
        Copilot::User.new(object).dotcom_chat_enabled?
      end

      field :is_copilot_mobile_chat_enabled, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether Copilot Chat for Mobile is enabled for this user", null: false

      def is_copilot_mobile_chat_enabled
        return false unless is_viewer
        Copilot::User.new(object).mobile_chat_enabled?
      end

      field :is_copilot_desktop_enabled,
        Boolean,
        required_capabilities: [:copilot_desktop],
        description: "Whether #{Copilot::COPILOT_DESKTOP} is enabled for this user",
        null: false

      def is_copilot_desktop_enabled
        return false unless is_viewer

        Copilot::User.new(object).desktop_enabled?
      end

      field :team_app_url, Scalars::URI, visibility: :internal, description: "The team app URL for this employee", null: true

      def team_app_url
        @object.thehub_url
      end

      field :github_stars_profile_url,
        Scalars::URI,
        description: "If this user is a GitHub Star, the URL to this user's GitHub Stars profile.",
        required_capabilities: [:mobile_only_schema_mask],
        null: true

      def github_stars_profile_url
        return unless @object.github_star?
        "#{GitHub.stars_program_url}/profiles/#{@object.display_login}/"
      end

      # Since this is only visible to `viewer`
      field :color_mode,
        Platform::Enums::ColorModeType,
        description: "The user's currently selected color mode. Only returns the value for yourself.",
        feature_flag: :issue_app_graphql_integration,
        null: true

      def color_mode
        return unless is_viewer

        @object.color_mode_with_default&.name
      end

      # Since this is only visible to `viewer`
      field :light_theme,
        Platform::Enums::ColorThemeType,
        description: "The user's currently selected light theme or day theme. Only returns the value for yourself.",
        feature_flag: :issue_app_graphql_integration,
        null: true

      def light_theme
        return unless is_viewer

        @object.light_theme&.name
      end

      # Since this is only visible to `viewer`
      field :dark_theme,
        Platform::Enums::ColorThemeType,
        description: "The users's current selected dark theme or night theme. Only returns the value for yourself.",
        feature_flag: :issue_app_graphql_integration,
        null: true

      def dark_theme
        return unless is_viewer

        @object.dark_theme&.name
      end

      field :is_bounty_hunter, Boolean, "Whether or not this user is a participant in the GitHub Security Bug Bounty.", null: false

      def is_bounty_hunter
        private_profile_boolean do
          object.bounty_hunter?
        end
      end

      field :is_campus_expert, Boolean, "Whether or not this user is a participant in the GitHub Campus Experts Program.", null: false

      def is_campus_expert
        private_profile_boolean do
          object.campus_expert?
        end
      end
      # Named this way so the field name has the capitalized H, i.e. isGitHubStar
      field :is_git_hub_star, Boolean, "Whether or not this user is a member of the GitHub Stars Program.", null: false

      def is_git_hub_star
        private_profile_boolean do
          object.github_star?
        end
      end

      field :is_spammy, Boolean, visibility: :internal, description: "Whether or not the user is spammy.", null: false, method: :spammy?

      field :is_hammy, Boolean, visibility: :internal, description: "Whether or not the user is hammy.", null: false, method: :hammy?

      field :viewer_can_follow, Boolean, description: "Whether or not the viewer is able to follow the user.", null: false

      def viewer_can_follow
        viewer = @context[:viewer]
        viewer.nil? ? false : Loaders::CanFollowCheck.load(viewer, @object.id)
      end

      field :viewer_can_block,
        Boolean,
        minimum_accepted_scopes: ["user"],
        description: "Could the viewer block the current user?",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def viewer_can_block(**arguments)
        context[:viewer].can_block(@object).blockable?
      end

      field :viewer_can_unblock,
        Boolean,
        minimum_accepted_scopes: ["user"],
        description: "Could the viewer unblock the current user?",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def viewer_can_unblock(**arguments)
        context[:viewer] != @object && @object.blocked_by?(context[:viewer])
      end

      field :is_employee, Boolean, description: "Whether or not this user is a GitHub employee.", null: false

      def is_employee
        @object.employee? && !GitHub.hidden_teamster?(@object)
      end

      field :via_actions, Boolean, description: "Whether the viewer was authenticated via the GitHub Actions integration.", null: true, visibility: :internal

      def via_actions
        return nil unless is_viewer
        Platform::Helpers::ViaActions.request_via_actions?(context: context)
      end

      field :is_developer_program_member, Boolean, description: "Whether or not this user is a GitHub Developer Program member.", null: false

      def is_developer_program_member
        private_profile_boolean do
          @object.async_developer_program_membership.then do |membership|
            !!membership.try(:active?)
          end
        end
      end

      field :is_prerelease_agreement_signed, Boolean, description: "Whether or not this user has signed the GitHub Prerelease Program agreement.", null: false do
        visibility :internal, environments: [:dotcom]
      end

      def is_prerelease_agreement_signed
        @object.async_prerelease_agreement.then do |_agreement|
          @object.prerelease_agreement_signed?
        end
      end

      field :is_org_prerelease_agreement_signed, Boolean, method: :async_org_prerelease_agreement_signed?, description: "Whether this user belongs to an org that has signed the GitHub Prerelease Program agreement.", null: false do
        visibility :internal, environments: [:dotcom]
      end

      field :is_site_admin, Boolean, description: "Whether or not this user is a site administrator.", null: false

      def is_site_admin
        private_profile_boolean do
          @object.async_two_factor_credential.then do
            @object.site_admin?
          end
        end
      end

      field :viewer_is_following, Boolean, description: "Whether or not this user is followed by the viewer. Inverse of isFollowingViewer.", null: false

      def viewer_is_following
        viewer = @context[:viewer]
        viewer.nil? ? false : Loaders::IsFollowingCheck.load(viewer.id, @object.id)
      end

      field :is_following_viewer, Boolean, description: "Whether or not this user is following the viewer. Inverse of viewerIsFollowing", null: false

      def is_following_viewer
        viewer = @context[:viewer]
        viewer.nil? ? false : Loaders::IsFollowingCheck.load(@object.id, viewer.id)
      end

      field :is_blocked_by_viewer, Boolean, "Whether or not this user is blocked by the viewer", null: false, visibility: :internal

      def is_blocked_by_viewer
        @object.blocked_by?(@context[:viewer])
      end

      field :is_account_successor_for_viewer, Boolean, description: "Whether or not this user is the viewer's account successor", null: false, visibility: :under_development

      def is_account_successor_for_viewer
        @object.account_successor_for?(@context[:viewer])
      end

      field :is_viewer, Boolean, description: "Whether or not this user is the viewing user.", null: false

      def is_viewer
        @object == @context[:viewer]
      end

      field :has_dismissed_notice, Boolean, visibility: :under_development, description: "Whether or not this user has dismissed the given notice", null: true do
        argument :notice, String, "Name of notice to check if dismissed", required: true
      end

      def has_dismissed_notice(**arguments)
        if is_viewer
          @object.dismissed_notice?(arguments[:notice])
        end
      end

      field :has_email, Boolean, visibility: :internal, description: "Whether or not this user has a profile email, which may or may not be visible to the viewing user.", null: false

      def has_email
        promises = Promise.all([@object.async_profile, @object.async_primary_user_email_role])
        promises.then do
          @object.publicly_visible_email(logged_in: true).present?
        end
      end

      field :show_private_contribution_count, Boolean, visibility: :under_development,
        description: "Does the user want their contributions to private repositories to be shown in the contributions graph and also summarized in the activity list on their profile?",
        null: false

      def show_private_contribution_count
        profile_settings = @object.profile_settings
        profile_settings.show_private_contribution_count?
      end

      field :activity_overview_enabled, Boolean, visibility: :under_development,
        description: "Does the user want the 'Activity overview' section shown on their profile?",
        null: false

      def activity_overview_enabled
        profile_settings = @object.profile_settings
        profile_settings.activity_overview_enabled?
      end

      field :action_invocation_blocked, Boolean, "Indicates if action invocation is blocked for this user", method: :action_invocation_blocked?, null: false, visibility: :internal

      field :stafftools_info, Objects::UserStafftoolsInfo, visibility: :internal, description: "User information only visible to site admin", null: true

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::AccountStafftoolsInfo.new(@object)
        else
          nil
        end
      end

      field :suspended_at, Scalars::DateTime, description: "Identifies the date and time when the user was suspended.", null: true do
        visibility :public, environments: [:enterprise]
        visibility :internal, environments: [:dotcom]
      end

      # This is needed for the `GET /user` REST API. It would be nicer to
      # expose a `Repository.collaborators` connection and grab the
      # `totalCount` from that instead, but doing that would require a way to
      # sum the `totalCount` values from all repositories. For now we'll just
      # use an internal field that gives us the data the REST API needs.
      field :collaborators_count, Integer, visibility: :internal, description: "The number of unique users who have access to this user's private repositories.", null: false

      # It could be nice to make this public someday. Presumably some
      # Enterprise users will want it, and it could just be null on dotcom.
      field :ldapDN, String, description: "The user's LDAP distinguished name.", null: true, visibility: :internal, resolver_method: :ldap_dn

      def ldap_dn
        @object.async_ldap_mapping.then do
          @object.ldap_dn
        end
      end

      field :is_large_bot_account, Boolean,
        visibility: :internal,
        description: "Returns true if the user is a large bot account.",
        null: false,
        method: :large_bot_account?

      field :is_large_scale_contributor, Boolean,
        visibility: :internal,
        description: "Returns true if the user is flagged as a large scale contributor.",
        null: false,
        method: :large_scale_contributor?

      field :plan, Objects::Plan, visibility: :internal, description: "The user's billing plan.", null: true

      def plan
        if is_viewer
          @object.async_plan
        else
          nil
        end
      end

      field :duration, String, visibility: :internal, description: "The user's billing cycle for their plan subscription e.g 'month', 'year'.", null: true

      def duration
        if is_viewer
          @context[:viewer]&.plan_duration || :month
        else
          nil
        end
      end

      field :has_apple_iap_subscription, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Indicates if a user's plan subscription is an apple iap subscription", null: false

      def has_apple_iap_subscription
        @object.async_plan_subscription.then do
          @object.apple_iap_subscription?
        end
      end

      field :has_two_factor_authentication_enabled, Boolean, visibility: :internal, description: "Indicates if the user has enabled two factor authentication.", null: true

      def has_two_factor_authentication_enabled
        if is_viewer
          @object.async_two_factor_credential.then do
            @object.two_factor_authentication_enabled?
          end
        else
          nil
        end
      end

      field :analytics_tracking_id, String, description: "The unique analytics tracking ID for this user", null: true do
        visibility :internal, environments: [:dotcom]
      end

      field :organization, Objects::Organization, description: "Find an organization by its login that the user belongs to.", null: true do
        argument :login, String, "The login of the organization to find.", required: true
      end

      def organization(**arguments)
        scope = @object.organizations

        org = scope.includes(:business).find_by_login(arguments[:login])
        return nil unless org
        public_member = org.public_member?(@object)
        return nil unless public_member || org.member_or_can_view_members?(@context[:viewer])

        if public_member
          @context[:permission].can_get_public_org_member? ? org : nil
        else
          @context[:permission].can_list_private_org_members?(org) ? org : nil
        end
      end

      field :contributions_collection, ContributionsCollection, description: "The collection of contributions this user has made to different repositories.", null: false do
        argument :organizationID, ID, "The ID of the organization used to filter contributions.", required: false,
          as: :organization_id # for legacy reasons, this is `organizationID` in GraphQL instead of `organizationId`
        argument :contribution_types, [Enums::ContributionsCollectionContributionType, null: true], <<~DESCRIPTION, required: false
          If provided, include only the specified types of contributions.
          Defaults to all types except issue comments (created repositories, commits, issues, pull requests,
          pull request reviews, joined GitHub, joined an organization, and anonymized contributions to GHE)
        DESCRIPTION
        argument :from, Scalars::DateTime, "Only contributions made at this time or later will be counted. If omitted, defaults to a year ago.", required: false
        argument :to, Scalars::DateTime, "Only contributions made before and up to (including) this time will be counted. If omitted, defaults to the current time or one year from the provided from argument.", required: false
        argument :lightweight, Boolean, required: false, default_value: false, visibility: :internal,
          description: "When true, the queries used to retrieve the contributions select minimal attributes."
      end

      def contributions_collection(**arguments)
        organization = if arguments[:organization_id]
          Helpers::NodeIdentification.typed_object_from_id([Objects::Organization],
                                                           arguments[:organization_id], @context)
        end

        time_range = build_and_validate_contributions_time_range(**arguments.slice(:to, :from))

        viewer = @context[:viewer] if @context[:permission].can_access_private_contributions?
        Loaders::ContributionCollector.load(
          user: @object,
          time_range: time_range,
          viewer: viewer,
          organization_id: organization&.id,
          contribution_classes: arguments[:contribution_types],
          excluded_organization_ids: @context[:unauthorized_organization_ids],
          lightweight: arguments[:lightweight],
        )
      end

      field :received_reviews, Connections.define(Objects::PullRequestReview), visibility: :internal, description: "Pull request reviews received by this user", null: false, connection: true

      def received_reviews
        return ArrayWrapper.new([]) unless is_viewer

        ::PullRequestReview
          .submitted
          .joins(:pull_request)
          .where(pull_requests: { user_id: @object.id })
          .order("pull_request_reviews.submitted_at DESC")
          .filter_spam_for(@context[:viewer])
      end

      field :saved_replies, Connections.define(Objects::SavedReply),
        minimum_accepted_scopes: ["read:user"],
        description: "Replies this user has saved",
        null: true,
        connection: true do
        argument :order_by, Inputs::SavedReplyOrder, "The field to order saved replies by.", required: false, default_value: { field: "updated_at", direction: "DESC" }
      end

      def saved_replies(**arguments)
        return ArrayWrapper.new([]) unless is_viewer

        if order_by = arguments[:order_by]
          ::SavedReply.where(user_id: @object.id).order "saved_replies.#{order_by[:field]} #{order_by[:direction]}"
        else
          ::SavedReply.where(user_id: @object.id)
        end
      end

      # NOTE: If you want to make this public, you'll need to fix the permission here:
      #
      # https://github.com/github/github/blob/698c661e629f44ac17e91aeea431d79f74c0a7f1/lib/platform/authorization/permission.rb#L683
      #
      # While this field is only being used by the app, it's fine to include all of the reviews requested
      # of the viewer. If apps are going to be requesting them on behalf of users, it'll need better permissions.
      #
      # Since this is only visible to `viewer`, spam filtering is a no-op
      field :reviews, Connections.define(Objects::PullRequestReview), visibility: :internal, description: "Pull request reviews created by this user", null: false, connection: true, exempt_from_spam_filter_check: true

      def reviews
        return ArrayWrapper.new([]) unless is_viewer

        ::PullRequestReview.submitted.where(user_id: @object.id).order("pull_request_reviews.submitted_at DESC")
      end

      # Since this is only visible to `viewer`, spam filtering is a no-op
      field :review_requests, Connections.define(Objects::ReviewRequest), visibility: :internal, description: "Review requests for this user", null: false, connection: true, exempt_from_spam_filter_check: true

      def review_requests
        return ArrayWrapper.new([]) unless is_viewer

        ::ReviewRequest.where(reviewer_id: @object.id).order("created_at DESC")
      end

      field :repositories_contributed_to, resolver: Resolvers::RepositoriesContributedTo, description: "A list of repositories that the user recently contributed to.", connection: true

      # We're going to bypass GraphQL-Ruby's built-in connection support
      # and manually return a connection object, so use `connection: false`
      field :repository_recommendations, Connections::RepositoryRecommendation, null: false,
        required_capabilities: [:mobile_only_schema_mask],
        connection: false do
        has_connection_arguments
        description <<~DESCRIPTION
            Returns recommendations for repositories that GitHub thinks the current viewer would find
            interesting.
          DESCRIPTION
        argument :mobile_sort_order, Boolean, description: "Display recommended repositories by mobile sort order", required_capabilities: [:mobile_only_schema_mask], required: false, default_value: false
      end

      def repository_recommendations(**arguments)
        user_to_fetch = if @context[:viewer] && @context[:viewer] == @object
          @object
        end

        ConnectionWrappers::RepositoryRecommendationConnection.new(
          user_to_fetch,
          first: arguments[:first],
          last: arguments[:last],
          before: arguments[:before],
          after: arguments[:after],
          arguments: arguments
        )
      end

      field :recent_interactions, [Objects::RecentInteraction], required_capabilities: [:mobile_only_schema_mask], description: "Objects the user has recently interacted with.", null: false do
        argument :types, [Enums::InteractableType, null: true], "Filter the objects the user has interacted with to just these types.", default_value: [:issue, :pull_request], required: false
        argument :limit, Integer, "How many recent interactions to return.", default_value: 10, required: false
        argument :since, Scalars::DateTime, <<~DESCRIPTION, required: false
            Cutoff time in the past. Only records with an interaction since then will be considered.
            Defaults to one week ago.
          DESCRIPTION
        argument :organizationID, ID,
          "Optional ID of an organization to use to filter the activity returned.",
          required: false,
          as: :organization_id # for legacy reasons, this is `organizationID` in GraphQL instead of `organizationId`
      end

      def recent_interactions(**arguments)
        result = if is_viewer
          types = arguments[:types] || [:issue, :pull_request]
          since = arguments[:since] || 2.weeks.ago
          limit = arguments[:limit] || 10
          org_global_id = arguments[:organization_id]

          org = if org_global_id
            Helpers::NodeIdentification.typed_object_from_id([Objects::Organization], org_global_id,
                                                             @context)
          end

          if types.include?(:issue) || types.include?(:pull_request)
            fetcher = ::Issue::RecentInteractions.new(
              @context[:viewer],
              since: since,
              types: types,
              organization_id: org.try(:id),
              excluded_account_ids: @context[:unauthorized_organization_ids],
            )
            fetcher.fetch(limit: limit) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          else
            []
          end
        else
          []
        end

        ArrayWrapper.new(result)
      end

      field :enterprise_repositories, Connections.define(Objects::Repository), description: <<~DESCRIPTION, null: false, connection: true, visibility: :internal, extras: [:itself]  do
          Repositories across Organizations within a single Enterprise where the User is an Organization Owner
        DESCRIPTION
        argument :slug, String, "The URL-friendly identifier for the enterprise.", required: true
        argument :phrase, String, "An optional search phrase to query for repositories across organizations", required: false
        argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories returned from the connection", required: false, default_value: { field: "created_at", direction: "DESC" }
        argument :exclude_archived, Boolean, "An optional filter to exclude archived repositories from the server response", required: false, default_value: false
      end

      def enterprise_repositories(**arguments)
        return Platform::ArrayWrapper.new([]) unless is_viewer

        Loaders::ActiveRecord.load(::Business, arguments[:slug], column: :slug).then do |business|
          filtered_organizations = business.filtered_organizations(
            viewer_role: "owner",
            viewer: @context[:viewer],
          )

          if filtered_organizations.any?
            org_filter = filtered_organizations.map { |org| "org:#{org.name}" }.join(" ")
            query = "#{org_filter} in:name #{arguments[:phrase]}"
            query += " archived:false" if arguments[:exclude_archived]

            resolver = Platform::Resolvers::Repositories.new(object: @object, context: @context, field: itself)
            resolver.resolve(order_by: arguments[:order_by],
                            owner_affiliations: nil,
                            query: query,
                            override_query_phrase: true,
                            )
          else
            Platform::ArrayWrapper.new([])
          end
        end
      end

      field :top_repositories, Connections.define(Objects::Repository), description: <<~DESCRIPTION, null: false, connection: true, extras: [:itself] do
          Repositories the user has contributed to, ordered by contribution rank, plus repositories the user has created
        DESCRIPTION

        argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories returned from the connection", required: true
        argument :since, Scalars::DateTime, "How far back in time to fetch contributed repositories", required: false
        argument :type, Enums::RepositoryType, "An optional type to use to filter the repositories", required_capabilities: [:mobile_only_schema_mask], required: false
        argument :has_issues_enabled, Boolean, "An optional flag used to filter the repositories based on having issues enable or not", required: false, visibility: :internal
        argument :owner, String, "Optionally return only repositories belonging to a certain owner", required: false, visibility: :internal
      end

      def top_repositories(itself:, **arguments)
        resolver = Platform::Resolvers::Repositories.new(object: @object, context: @context, field: itself)

        if @object.private_profile_for?(context[:viewer])
          user_repos = resolver.resolve(order_by: arguments[:order_by], owner_affiliations: [:owned], type: arguments[:type]).to_a
          ranked_repos = []
        else
          user_repos = resolver.resolve(order_by: arguments[:order_by], affiliations: [:owned, :direct],
            owner_affiliations: [:owned, :direct], type: arguments[:type], has_issues_enabled: arguments[:has_issues_enabled]).to_a
          ranked_repos = ranked_contributed_repositories(
            exclude_owned: false,
            since: arguments[:since],
            repo_type: arguments[:type],
            has_issues_enabled: arguments[:has_issues_enabled],
          )
        end

        all_repos = ranked_repos + user_repos
        if !arguments[:owner].nil?
          all_repos = all_repos.select { |repo| repo.owner_display_login == arguments[:owner] }
        end
        ArrayWrapper.new(all_repos.uniq(&:id))
      end

      def ranked_contributed_repositories(**arguments)
        # falling back to an empty array in case of service unavailability issues (like outages)
        fallback = ArrayWrapper.new([])

        with_database_error_fallback(fallback:) do
          if @object.large_bot_account?
            # FIXME: This quick exit for the large_bot_account can be removed once we
            # have solved the performance issues surrounding contribution graphs.
            #
            # see https://github.com/github/core-app/issues/84
            ArrayWrapper.new([])
          else
            since = arguments[:since] || 1.year.ago
            since = 1.year.ago if since < 1.year.ago
            since = 1.year.ago if since > Time.zone.now
            repositories = @object.repositories_contributed_to(
              viewer: @context[:viewer],
              limit: nil,
              exclude_owned: arguments[:exclude_owned],
              since: since,
              repo_type: arguments[:repo_type],
              has_issues_enabled: arguments[:has_issues_enabled]
            )

            cap_result = context[:cap_filter].evaluate(repositories, exclude: context[:cap_exclude_policies] || [])

            repositories = cap_result.authorized.resources

            ArrayWrapper.new(repositories.compact.select(&:active?))
          end
        end
      end

      field :organizations_contributed_to, Connections.define(Objects::Organization), visibility: :under_development, connection: true, null: false, description: "A ranked list of organizations this user has contributed to" do
        argument :to, Scalars::DateTime, "Only contributions made before and up this time will be counted. If omitted, defaults to the current time.", required: false
        argument :from, Scalars::DateTime, "Only contributions made at this time or later will be counted. If omitted, defaults to a year ago.", required: false
        argument :selectedOrganizationID, ID, "An optional ID for an organization that will be included in the results even if no contributions were made to that organization.", required: false,
          as: :selected_organization_id
        argument :lightweight, Boolean, required: false, default_value: false, visibility: :internal,
          description: "When true, the queries used to retrieve the contributions select minimal attributes."
      end

      def organizations_contributed_to(**arguments)
        arguments[:lightweight] = false if arguments[:lightweight].nil?
        time_range = build_and_validate_contributions_time_range(**arguments.slice(:to, :from))

        viewer = @context[:viewer] if @context[:permission].can_access_private_contributions?
        loader_args = {
          user: @object,
          time_range: time_range,
          viewer: viewer,
          organization_id: nil,
          excluded_organization_ids: @context[:unauthorized_organization_ids],
          lightweight: arguments[:lightweight],
        }

        Loaders::ContributionCollector.load(**loader_args).then do |collector|
          org = if arguments[:selected_organization_id]
            Helpers::NodeIdentification.
              typed_object_from_id([Objects::Organization], arguments[:selected_organization_id],
                                   context)
          end
          collector.organizations_contributed_to(selected_organization_id: org&.id)
        end
      end

      field :commit_comments, resolver: private_profile_collection(Resolvers::CommitComments), description: "A list of commit comments made by this user.", connection: true

      field :pull_requests, resolver: private_profile_collection(Resolvers::UserPullRequests), description: "A list of pull requests associated with this user.", connection: true

      field :issues_and_pull_requests, resolver: private_profile_collection(Resolvers::IssuesAndPullRequests), description: "A list of pull requests and issues associated with this user.", visibility: :under_development, connection: true

      field :issues, resolver: private_profile_collection(Resolvers::Issues), description: "A list of issues associated with this user.", connection: true

      field :gist_comments, resolver: private_profile_collection(Resolvers::GistComments), description: "A list of gist comments made by this user.", connection: true

      field :issue_comments, resolver: private_profile_collection(Resolvers::IssueComments), description: "A list of issue comments made by this user.", connection: true

      field :public_keys, Connections.define(Objects::PublicKey),
        null: false,
        description: "A list of public keys associated with this user."

      def public_keys
        if context[:permission].access_allowed?(:read_user_public, resource: Platform::PublicResource.new, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true) # rubocop:todo GitHub/PublicResource
          object.public_keys.scoped
        else
          ::PublicKey.none
        end
      end

      field :following, Connections::Following, description: "A list of users the given user is following.", null: false, connection: true do
        argument :user_database_ids, [Integer, null: true], "Optional list of user IDs to filter results. If provided, only following users in this list will be returned",
          visibility: :internal, required: false
        argument :order_by, Inputs::FollowOrder, "How to order the followed users. Defaults to most recently followed users first.", required: false,
          visibility: :under_development, default_value: { field: "followed_at", direction: "DESC" }
      end

      def following(user_database_ids: nil, order_by: nil)
        order_by ||= { field: "followed_at", direction: "DESC" }
        return Following.none if @object.private_profile_for?(@context[:viewer])

        scope = @object.followings.filter_spam_for(@context[:viewer])
        scope = scope.where(following_id: user_database_ids) if user_database_ids
        scope = scope.order(created_at: order_by[:direction]) if order_by[:field] == "followed_at"

        scope
      end

      field :followers, Connections::Follower, description: "A list of users the given user is followed by.", null: false, connection: true do
        argument :order_by, Inputs::FollowOrder, "How to order the followers. Defaults to most recent followers first.", required: false,
          visibility: :under_development, default_value: { field: "followed_at", direction: "DESC" }
      end

      def followers(order_by: nil)
        order_by ||= { field: "followed_at", direction: "DESC" }
        return Following.none if @object.private_profile_for?(@context[:viewer])

        scope = @object.followeds.filter_spam_for(@context[:viewer], skip_user_filter_if_not_spammy: true)
        scope = scope.order(created_at: order_by[:direction]) if order_by[:field] == "followed_at"
        scope
      end

      field :gist, Objects::Gist, description: "Find gist by repo name.", null: true do
        argument :name, String, "The gist name to find.", required: true
      end

      def gist(**arguments)
        Loaders::ActiveRecord.load(::Gist, arguments[:name], column: :repo_name)
      end

      field :gists, resolver: private_profile_collection(Resolvers::Gists), description: "A list of the Gists the user has created.", connection: true

      field :watching, resolver: private_profile_collection(Resolvers::WatchedRepositories), description: "A list of repositories the given user is watching.", connection: true

      field :organizations, resolver: Resolvers::Organizations, description: "A list of organizations the user belongs to.", connection: true

      field :suggested_issue_type_names, [String], description: "A list of suggested organizational issue type names that the user has access to.", visibility: :internal do
        argument :limit, Integer, required: false, default_value: 50, description: "Optionally limit how many suggested issue types to return, defaults to 50, maximum of 100."
      end

      def suggested_issue_type_names(**arguments)
        limit = arguments[:limit].clamp(1, 100)

        @object.async_batch_accessible_suggested_issue_type_names(@context[:viewer], @context[:cap_filter]).then do |issue_types|
          Platform::ArrayWrapper.new(issue_types.take(limit) || [])
        end
      end

      field :member_organizations, [Organization], visibility: :under_development, null: false,
          description: <<~DESCRIPTION do
            A list of the organizations this user belongs to, including those the user is a billing
            manager of if the viewer is the user.
          DESCRIPTION
        argument :limit, Integer, required: false, default_value: 10,
          description: "How many organizations to return."
      end

      def member_organizations(**arguments)
        limit = arguments[:limit].clamp(1, 100)

        if is_viewer
          orgs_belonged_to = @object.organizations.includes(:profile).limit(limit).
            filter_spam_for(@context[:viewer])
          orgs_managed = @object.billing_manager_organizations.includes(:profile).limit(limit).
              filter_spam_for(@context[:viewer])
          all_orgs = orgs_belonged_to | orgs_managed
          all_orgs.take(limit)
        elsif @object.private_profile_for?(@context[:viewer])
          Platform::ArrayWrapper.new([])
        else
          @object.public_organizations.includes(:profile).limit(limit).
            filter_spam_for(@context[:viewer])
        end
      end

      # Since this is only visible to `viewer`, spam filtering is a no-op
      field :owned_organizations, Connections.define(Objects::Organization), visibility: :internal, exempt_from_spam_filter_check: true, null: false, connection: true, description: <<~DESCRIPTION do
          A list of the organizations the user owns. Returns an empty list for a user other than
          the current viewer.
        DESCRIPTION

        argument :only_non_business_organizations, Boolean, required: false, default_value: false,
          description: "When true, response only includes Organizations that don't belong to a Business"
      end

      def owned_organizations(**arguments)
        if is_viewer
          organizations = @object.owned_organizations

          if arguments[:only_non_business_organizations]
            organizations = organizations
              .joins("LEFT OUTER JOIN business_organization_memberships ON business_organization_memberships.organization_id = users.id")
              .where("business_organization_memberships.id IS NULL")
          end

          organizations
        else
          Platform::ArrayWrapper.new([])
        end
      end

      field :enterprises, Connections.define(Objects::Enterprise), "A list of enterprises that the user belongs to.",
        minimum_accepted_scopes: ["read:enterprise"],
        null: true, connection: true do
        argument :order_by, Inputs::EnterpriseOrder,
          "Ordering options for the User's enterprises.",
          required: false, default_value: { field: "name", direction: "ASC" }

        argument :membership_type, Platform::Enums::EnterpriseMembershipType,
          "Filter enterprises returned based on the user's membership type.",
          required: false, default_value: :all
      end

      def enterprises(**arguments)
        unless is_viewer || self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new("viewer does not have permission to list enterprises information.")
        end

        businesses = @object.businesses(membership_type: arguments[:membership_type])

        if order_by = arguments[:order_by]
          businesses = businesses.order "businesses.#{order_by[:field]} #{order_by[:direction]}"
        end

        businesses
      end

      field :owned_organization, Objects::Organization, visibility: :internal, description: "Look up an organization owned by the current viewer that has the given login.", null: true do
        argument :login, String, "The organization's login.", required: true
      end

      def owned_organization(**arguments)
        if @context[:viewer] == @object
          @object.owned_organizations.where(login: arguments[:login]).first
        end
      end

      field :hovercard, Objects::Hovercard, description: "The hovercard information for this user in a given context", null: false do
        argument :primary_subject_id, ID, "The ID of the subject to get the hovercard in the context of", required: false
      end

      def hovercard(primary_subject_id: nil)
        viewer = @context[:viewer]

        primary_subject = nil
        if primary_subject_id
          begin
            primary_subject = Helpers::NodeIdentification.typed_object_from_id([Objects::Issue, Objects::SponsorsListing, Objects::PullRequest, Objects::Organization, Objects::Repository], primary_subject_id, @context)
          rescue Errors::NotFound
            raise Errors::NotFound, "Could not find the primary subject"
          end
        end

        ::UserHovercard.new(@object, primary_subject, viewer: viewer)
      end

      field :teams, Connections.define(Objects::Team), visibility: :internal, null: false, connection: true, description: <<~DESCRIPTION do
        A list of the teams the user belongs to that are visible to the viewer.
      DESCRIPTION
        argument :order_by, Inputs::TeamOrder,
          "Ordering options for teams returned from the connection. If omitted, teams will be ranked based on the user's activity within them.",
          required: false
        argument :organizationID, ID,
          "Optional ID of an organization to use to filter the teams returned.", required: false, as: :organization_id
      end

      def teams(**arguments)
        @object.async_visible_teams_for(context[:viewer]).then do |scope|
          cap_authorized_team_ids = context[:cap_filter].authorized_resource_ids(scope)
          scope = scope.where(id: cap_authorized_team_ids)

          if order_by = arguments[:order_by]
            order = "#{order_by[:field]} #{order_by[:direction]}"
            scope = scope.order(order)
          else
            scope = ::Team.ranked_for(@object, scope: scope)
          end

          if org_global_id = arguments[:organization_id]
            Helpers::NodeIdentification.async_typed_object_from_id(Objects::Organization, org_global_id, context).then do |org|
              if org
                scope.owned_by(org)
              else
                scope
              end
            end
          else
            scope
          end
        end
      end

      field :starred_repositories, resolver: Resolvers::StarredRepositories, description: "Repositories the user has starred.", null: false, connection: false

      field :starred_topics, visibility: :under_development, required_capabilities: [:mobile_only_schema_mask], resolver: Resolvers::StarredTopics,
        description: "Topics the user has starred.", null: false, connection: true

      field :adminable_apps, Connections.define(Objects::App), visibility: :internal, description: "A list of GitHub Apps managed by this user.", null: false, connection: true do
        argument :exclude_marketplace_listings, Boolean, <<~DESCRIPTION, required: false
            Filters apps to exclude those that have a Marketplace listing. If omitted,
            integrations that are in the Marketplace will be included.
          DESCRIPTION
        argument :public_only, Boolean, <<~DESCRIPTION, required: false
            Filters apps so only public apps are returned. If omitted or false, both
            public and internal apps will be returned.
          DESCRIPTION
      end

      def adminable_apps(**arguments)
        if is_viewer
          scope = ::Integration.adminable_by(@context[:viewer]).not_for_github_connect
          scope = scope.not_in_marketplace if arguments[:exclude_marketplace_listings]
          scope = scope.public if arguments[:public_only]
          scope = scope.where.not(owner_id: @context[:unauthorized_organization_ids])
          scope.order("integrations.updated_at DESC")
        else
          Platform::ArrayWrapper.new([])
        end
      end

      field :adminable_oauth_applications, Connections.define(Objects::OauthApplication), visibility: :internal, description: "A list of OAuth applications managed by this User.", null: false, connection: true do
        argument :exclude_marketplace_listings, Boolean, "Filters OAuth applications to exclude those that have a Marketplace listing. If omitted, OAuth applications that are in the Marketplace will be included.", required: false
      end

      def adminable_oauth_applications(**arguments)
        if is_viewer
          scope = ::OauthApplication.adminable_by(@context[:viewer])
          scope = scope.not_in_marketplace if arguments[:exclude_marketplace_listings]
          scope = scope.where.not(user_id: @context[:unauthorized_organization_ids])
          scope.order("oauth_applications.updated_at DESC")
        else
          Platform::ArrayWrapper.new([])
        end
      end

      field :adminable_actions, Connections.define(Objects::RepositoryAction), visibility: :internal, description: "A list of actions managed by this User.", null: false, connection: true do
        argument :exclude_marketplace_listings, Boolean, "Filters actions to exclude those that have a Marketplace listing. If omitted, actions that are in the Marketplace will be included.", required: false, default_value: false
        argument :order_by, Inputs::RepositoryActionOrder, "Ordering options for actions returned from the connection.", required: false, default_value: { field: "updated_at", direction: "DESC" }
      end

      def adminable_actions(**arguments)
        if is_viewer
          scope = ::RepositoryAction.adminable_by(@context[:viewer])
          scope = scope.not_in_marketplace if arguments[:exclude_marketplace_listings]
          scope = scope.joins(:repository).where.not(repositories: { owner_id: @context[:unauthorized_organization_ids] })
          scope.order("repository_actions.#{arguments[:order_by][:field]} #{arguments[:order_by][:direction]}")
        else
          Platform::ArrayWrapper.new([])
        end
      end

      field :authentication_records, Connections.define(Objects::AuthenticationRecord), null: false, connection: true do
        description "A list of successful logins for a user"
        argument :since, Scalars::DateTime, "return records created after a certain time", required: true
        visibility :internal
      end

      def authentication_records(since:, country_code: nil, octolytics_id: nil)
        if is_viewer
          @object.authentication_records.recent(since)
        else
          ::AuthenticationRecord.none
        end
      end

      field :order_preview, Objects::MarketplaceOrderPreview, visibility: :internal, description: "The user's order preview for a Marketplace listing.", null: true do
        argument :listing_slug, String, "The slug for the Marketplace listing", required: true
      end

      def order_preview(**arguments)
        Loaders::ActiveRecord.load(::Marketplace::Listing, arguments[:listing_slug], column: :slug).then do |listing|
          next unless listing

          Marketplace::OrderPreview.
            with_valid_listing_data.
            where(user_id: @object.id, marketplace_listing_id: listing.id).
            first
        end
      end

      field :order_previews, Platform::Connections.define(Objects::MarketplaceOrderPreview), visibility: :internal, description: "The user's pending Marketplace orders", null: false, connection: true do
        argument :only_retargeting_notice_triggered, Boolean, "Only returns order previews for which a retargeting notice has been triggered", required: false, default_value: false
      end

      def order_previews(**arguments)
        relation = @object.marketplace_order_previews.with_valid_listing_data.order(:viewed_at)
        relation = relation.retargeting_notice_triggered if arguments[:only_retargeting_notice_triggered]
        relation
      end

      field :marketplace_subscriptions, Connections::SubscriptionItem, numeric_pagination_enabled: true, visibility: :internal, description: "A list of Marketplace subscriptions for a user.", null: false, connection: true do
        argument :marketplace_listing_id, ID, "Limit subscriptions to a particular Marketplace listing", required: false
      end

      def marketplace_subscriptions(**arguments)
        return ArrayWrapper.new([]) unless is_viewer

        subscription_items = Billing::SubscriptionItem.with_marketplace_listing_plans_type
          .joins(:plan_subscription)
          .where(plan_subscriptions: { user_id: @object.user_or_org_account_ids }).active

        if arguments[:marketplace_listing_id]
          marketplace_listing = Platform::Helpers::NodeIdentification.typed_object_from_id(
            [Objects::MarketplaceListing],
            arguments[:marketplace_listing_id],
            @context,
          )

          listing_plans_ids = Marketplace::ListingPlan.where(
            marketplace_listing_id: marketplace_listing.id,
          ).pluck(:id)

          subscription_items = subscription_items.where(subscribable_id: listing_plans_ids)
        end

        subscription_items
      end

      field :pending_marketplace_installations, Connections::SubscriptionItem, visibility: :internal, description: "Subscription items for apps that are not installed", null: false do
        argument :only_notice_triggered, Boolean, "Only returns pending installations for which a notice has been triggered", required: false, default_value: false
      end

      def pending_marketplace_installations(only_notice_triggered: false)
        return Billing::SubscriptionItem.none unless is_viewer

        @object.pending_marketplace_installations(only_notice_triggered: only_notice_triggered)
      end

      field :user_sessions, Connections.define(Objects::UserSession), visibility: :internal, description: "The currently logged in user sessions for the viewer", null: false, connection: true do
        argument :recent, Boolean, "Limit sessions to recently used, active sessions", required: false
      end

      def user_sessions(recent: false)
        if is_viewer
          if recent
            @object.sessions.user_facing.recent
          else
            @object.sessions.user_facing
          end
        else
          ::UserSession.none
        end
      end

      field :mobile_auth_status, Objects::MobileAuthStatus, description: "The status of mobile auth keys and requests associated with this user.", null: true, required_capabilities: [:mobile_only_schema_mask]

      def mobile_auth_status
        raise Errors::Forbidden.new("#{@object.display_login} is not authorized to perform mobile authentication device actions.") unless is_viewer

        begin
          mobile_device_manager = ::GitHub::Authnd.mobile_device_manager("github/account_login")
          auth_response = mobile_device_manager.find_active_device_auth(@object.id, context[:viewer].oauth_access.try(:id))
        rescue Faraday::Error
          raise Errors::ServiceUnavailable.new("Mobile device authentication actions are currently unavailable. Please try again later.")
        rescue ::Authnd::Proto::Error
          raise Errors::Unprocessable.new("Error occurred while fetching active mobile auth request.")
        end

        result = {
            has_valid_device_auth_key: auth_response.has_valid_device_key,
            has_expired_auth_request: auth_response.has_expired_auth_request,
            user_id: context[:viewer].id
          }

        if auth_response.result == :RESULT_NOT_FOUND
          return  result
        elsif !auth_response.success?
          raise Errors::Unprocessable.new("Failed to fetch active mobile auth request.")
        end

        if auth_response.has_valid_device_key
          supported_request_types = %w[2fa_login device_verification 2fa_password_reset 2fa_sudo_challenge]
          request_type = auth_response.type.in?(supported_request_types) ? auth_response.type : "unknown"
          result[:active_auth_request] = {
              id: auth_response.id,
              payload: auth_response.payload,
              challenge_required: auth_response.challenge_required,
              type: request_type
          }
        end
        result
      end

      field :mobile_push_notification_schedules, Connections.define(Objects::MobilePushNotificationSchedule), required_capabilities: [:mobile_only_schema_mask], null: false,
        description: "A list of mobile push notification schedules associated with this user."

      def mobile_push_notification_schedules
        return ArrayWrapper.new([]) unless @object == context[:viewer]

        schedules = handle_newsies_service_unavailable do
          Newsies::MobilePushNotificationSchedule
            .where(user_id: @object.id)
            .order(day: :asc)
            .all
        end

        ArrayWrapper.new(schedules)
      end

      field :mobile_push_notification_settings, Objects::MobilePushNotificationSettings, required_capabilities: [:mobile_only_schema_mask], null: true,
        description: "A list of mobile push notification settings associated with this user."

      def mobile_push_notification_settings
        return nil unless @object == context[:viewer]

        @object.async_mobile_push_notification_setting.then do |settings|
          next settings unless settings.nil?

          # Returns an unsaved MobilePushNotificationSetting with all push options disabled
          MobilePushNotificationSetting.new(user: @object)
        end
      end

      field :notification_threads, Connections::NotificationThread, minimum_accepted_scopes: ["notifications"], required_capabilities: [:mobile_only_schema_mask, :access_internal_graphql_notifications], null: false do
        description <<~DESCRIPTION
          A list of notification threads for the viewer. Returns an empty list for a user other than
          the current viewer.

          Combining both filterBy and query arguments will result in an error.
          Please favor using the query argument.
        DESCRIPTION

        argument :filter_by, Inputs::NotificationThreadFilters, "Filtering options for notifications. Will soon be deprecated.", required: false
        argument :query, String, "The search string to look for. If no is:read, is:unread, or is:done qualifiers are included in the query, results will include read and unread notification threads by default.", required: false
      end

      def notification_threads(filter_by: nil, query: nil)
        # If _anything_ is set for both arguments, we raise.
        raise Errors::ArgumentError, "Cannot combine filterBy and query arguments." if !filter_by.nil? && !query.nil?

        return Platform::ArrayWrapper.new([]) unless context[:permission].can_list_user_notifications?(@object)

        # indirect orgs are those that the user is not a direct member of,
        # but still needs to satisfy conditional access policies in order to view their notifications.
        # e.g. public orgs belonging to the same business that the user belongs to.
        unauthorized_account_ids = unauthorized_account_ids(@context[:viewer], @context[:cap_filter])

        if !query
          return Platform::Helpers::NotificationThreadsQuery.new({
            filter_by: filter_by,
            unauthorized_account_ids: unauthorized_account_ids,
            internal_request: Platform.safe_origin?(@context[:origin]),
            feature_flags: @context[:feature_flags],
          }, @context[:viewer])
        end

        Platform::Helpers::NotificationThreadsQuery.new({
          query: query,
          unauthorized_account_ids: unauthorized_account_ids,
          internal_request: Platform.safe_origin?(@context[:origin]),
          feature_flags: @context[:feature_flags],
        }, @context[:viewer])
      end

      field :notifications, Connections::NotificationThread, visibility: :under_development, null: false do
        description <<~DESCRIPTION
          NOTE: FOR HYPERLIST USE ONLY. DO NOT USE THIS FIELD IN ANY OTHER CONTEXT.
          A list of notifications for the viewer. Returns an empty list for a user other than
          the current viewer.
          Combining both filterBy and query arguments will result in an error.
          Please favor using the query argument.
        DESCRIPTION

        argument :query, String, "The search string to look for. If no is:read, is:unread, or is:done qualifiers are included in the query, results will include read and unread notification threads by default.", required: false
      end

      def notifications(query: nil)
        return Platform::ArrayWrapper.new([]) unless context[:permission].can_list_user_notifications?(@object)

        # indirect orgs are those that the user is not a direct member of,
        # but still needs to satisfy conditional access policies in order to view their notifications.
        # e.g. public orgs belonging to the same business that the user belongs to.
        unauthorized_account_ids = unauthorized_account_ids(@context[:viewer], @context[:cap_filter])

        Platform::Helpers::NotificationsQuery.new({
          query: query,
          unauthorized_account_ids: unauthorized_account_ids
        }, @context[:viewer])
      end

      field :notification_repositories, [Objects::RepositoryNotificationCounts], visibility: :under_development, null: false do
        description <<~DESCRIPTION
          NOTE: FOR THE NEW INBOX USE ONLY.
          A list of repositories for the viewer with pending notifications.
          Counts the number of outstanding notifications per repository for this user.
        DESCRIPTION

        argument :limit, Integer, required: false, default_value: 10, description: "How many repositories to return."
      end

      def notification_repositories(**arguments)
        return Platform::ArrayWrapper.new([]) unless context[:permission].can_list_user_notifications?(@object)

        if @object == @context[:viewer]
          @object.repo_notification_counts(
            cap_filter: @context[:cap_filter],
            limit: arguments[:limit]
          )
        end
      end

      field :notification_filters, Connections.define(Platform::Objects::NotificationFilter), required_capabilities: [:mobile_only_schema_mask], minimum_accepted_scopes: ["notifications"], null: false do
        description <<~DESCRIPTION
          A list of notification filters for the viewer. Returns an empty list for any user
          other than the current viewer.
        DESCRIPTION
      end

      def notification_filters
        return ArrayWrapper.new([]) unless context[:permission].can_list_user_notifications?(@object)
        ArrayWrapper.new(unpack_newsies_response!(GitHub.newsies.web.all_custom_inboxes(@object)))
      end

      field :notification_settings, Objects::NotificationSettings, description: "The viewer's notification settings", required_capabilities: [:mobile_only_schema_mask], null: true

      def notification_settings
        if @object == context[:viewer]
          @object.async_profile.then do
            @object.async_primary_user_email.then do
              settings = Notifications::Settings.settings(@object)
              raise Errors::ServiceUnavailable.new("Notifications features are currently unavailable.") if settings.nil?
              { user: @object, settings: settings }
            end
          end
        else
          nil
        end
      end

      field :notification_lists_with_thread_count, Connections.define(Objects::NotificationListWithThreadCount), minimum_accepted_scopes: ["notifications"], required_capabilities: [:mobile_only_schema_mask], null: false do
        description <<~DESCRIPTION
          A list of notification lists the viewer has received a notification for. Returns an empty list for a user other than
          the current viewer.
        DESCRIPTION

        argument :statuses, [Platform::Enums::NotificationStatus], "Only return lists which have at least one notification thread with a status in this list", required: false
        argument :list_types, [Platform::Enums::NotificationThreadSubscriptionListType], "Only return lists where the list type is in the list", required: false
      end

      def notification_lists_with_thread_count(statuses: [], list_types: [])
        return ArrayWrapper.new([]) unless context[:permission].can_list_user_notifications?(@object)

        # Filter lists by notification status. Default to ALL status types by default.
        options = {
          statuses: statuses.presence,
          list_type: list_types.presence,
        }.compact

        counts_by_list = unpack_newsies_response!(GitHub.newsies.web.counts_by_list(@object, options))
                          .sort_by { |(_, _, count_unread)| -count_unread }

        # indirect orgs are those that the user is not a direct member of,
        # but still needs to satisfy conditional access policies in order to view their notifications.
        # e.g. public orgs belonging to the same business that the user belongs to.
        unauthorized_account_ids = unauthorized_account_ids(@context[:viewer], @context[:cap_filter])

        readable_lists_with_thread_count_promises = counts_by_list
          .map do |(list, count_all, count_unread)|
            notification_list_with_thread_count = Platform::Models::NotificationListWithThreadCount.new(
              list: list,
              count: count_all,
              unread_count: count_unread,
              user: @object,
            )

            notification_list_with_thread_count.async_readable_by?(@context[:viewer], unauthorized_account_ids: unauthorized_account_ids).then do |readable|
              next notification_list_with_thread_count if readable
            end
          end

        Promise.all(readable_lists_with_thread_count_promises).then do |readable_lists_with_thread_count|
          ArrayWrapper.new(readable_lists_with_thread_count.compact)
        end
      end

      def self.load_from_params(params)
        Loaders::ActiveRecord.load(::User, params[:user_id], column: :login)
      end

      field :organization_verified_domain_emails,
        [String],
        minimum_accepted_scopes: ["read:org"],
        description: "Verified email addresses that match verified domains for a specified organization the user is a member of.",
        map_to_service: :verifiable_domains,
        null: false do
          argument :login, String, description: "The login of the organization to match verified domains from.", required: true
        end

      def organization_verified_domain_emails(**arguments)
        Loaders::ActiveRecord.load(::Organization, arguments[:login], column: :login, case_sensitive: false).then do |organization|
          next [] unless organization.present?
          organization.async_business.then do
            next [] unless context[:permission].can_access_organization_domain_emails?(organization)

            organization.async_can_view_domain_emails?(context[:viewer]).then do |can_view|
              next [] unless can_view

              organization.async_supports_showing_verified_domain_emails?.then do |is_supported|
                next [] unless is_supported

                @object.async_eligible_emails_for(
                  organization, include_approved: false
                ).then do |emails|
                  emails.map(&:email)
                end
              end
            end
          end
        end
      end

      field :can_receive_organization_emails_when_notifications_restricted,
        Boolean,
        minimum_accepted_scopes: ["read:org"],
        description: "Could this user receive email notifications, if the organization had notification restrictions enabled?",
        visibility: :public,
        map_to_service: :verifiable_domains,
        null: false do
          argument :login, String, description: "The login of the organization to check.", required: true
        end

      def can_receive_organization_emails_when_notifications_restricted(**arguments)
        Loaders::ActiveRecord.load(::Organization, arguments[:login], column: :login, case_sensitive: false).then do |organization|
          next false unless organization.present?
          organization.async_business.then do
            next false unless context[:permission].can_access_organization_domain_emails?(organization)

            organization.async_can_view_domain_emails?(context[:viewer]).then do |can_view|
              next false unless can_view

              organization.async_supports_showing_verified_domain_emails?.then do |is_supported|
                next false unless is_supported

                @object.async_eligible_emails_for(organization).then do |emails|
                  emails.any?
                end
              end
            end
          end
        end
      end

      field :toggleable_features, Connections.define(Objects::ToggleableFeature), description: "Features that the user can enroll and unenroll in.", null: true, visibility: :under_development, map_to_service: :features

      def toggleable_features
        if is_viewer
          context[:viewer].available_prerelease_features
        end
      end

      field :can_admin_marketplace_listings, Boolean, "Can the user administer Marketplace listings.", null: false, visibility: :internal, method: :can_admin_marketplace_listings?

      field :dashboard, Objects::UserDashboard, description: "Dashboard for this user.", null: true, required_capabilities: [:mobile_only_schema_mask]

      def dashboard
        return nil if object != context[:viewer]

        object.async_dashboard.then do |dashboard|
          dashboard.presence || ::UserDashboard.new(user: object)
        end
      end

      field :dashboard_pinned_items, resolver: Resolvers::DashboardPinnedItems,
        description: "A list of items this user has pinned to their dashboard.",
        connection: true, required_capabilities: [:mobile_only_schema_mask]

      field :dashboard_pinned_items_remaining, Int, null: false,
        description: "Returns how many more items this user can pin to their dashboard.",
        visibility: :internal

      field :mobile_time_zone, String, description: "The user's mobile time zone.", required_capabilities: [:mobile_only_schema_mask], null: false

      def mobile_time_zone
        @object.async_mobile_time_zone.then(&:name)
      end

      field :advisory_credits, Connections.define(Objects::AdvisoryCredit), "Credits given to the user for collaborating on security advisories", null: false, visibility: :under_development do
        argument :order_by, Inputs::AdvisoryCreditOrder, "Ordering options for the returned credits.", required: false, default_value: { field: "id" }
      end

      def advisory_credits(order_by:)
        object.advisory_credits.accepted.on_public_repository_advisories
      end

      field :interaction_ability, Objects::RepositoryInteractionAbility, "The interaction ability settings for this user.", null: true

      def interaction_ability
        @object.async_can_read_interaction_limits?(context[:viewer]).then do |can_read|
          next unless can_read
          Platform::Models::RepositoryInteractionAbility.new(@object)
        end
      end

      field :lists, Connections.define(Objects::UserList), "A user-curated list of repositories", null: false, connection: true do
        argument :order_by, Inputs::UserListOrder, "Ordering options for the returned lists", required: false, default_value: { field: "last_added_at", direction: "DESC" }
      end

      def lists(order_by: nil)
        order_by ||= { field: "last_added_at", direction: "DESC" }
        order_value = { order_by[:field] => order_by[:direction] }

        if is_viewer
          object.lists.order(order_value)
        else
          object.lists.where(private: false).order(order_value)
        end
      end

      field :can_create_lists, Boolean, "Whether this user can create lists.", null: false, required_capabilities: [:mobile_only_schema_mask]

      def can_create_lists
        return false unless is_viewer
        @object.can_create_lists?
      end

      field :suggested_list_names, [Objects::UserListSuggestion], "Suggested names for user lists", null: false

      def suggested_list_names
        ::UserList::DEFAULT_SUGGESTIONS.map { |s| Platform::Models::UserListSuggestion.new(name: s) }
      end

      field :has_created_lists, Boolean, "Whether this user has created lists.", null: false, required_capabilities: [:mobile_only_schema_mask]

      def has_created_lists
        return false unless is_viewer
        @object.has_created_lists?
      end

      field :private_profile, Boolean, "Whether user's profile is currently private", null: false, required_capabilities: [:mobile_only_schema_mask]

      field :pull_request_user_preferences, Objects::PullRequestUserPreferences, "The user's pull request settings", null: false

      def pull_request_user_preferences
        if is_viewer
          @object.pull_request_user_preferences
        end
      end

      field :achievement, resolver: private_profile_field(Resolvers::UserAchievement), null: true, required_capabilities: [:mobile_only_schema_mask],
        description: "Return a specific achievement that this user has unlocked."

      field :achievements, resolver: private_profile_collection(Resolvers::UserAchievements), null: false, required_capabilities: [:mobile_only_schema_mask],
        description: "Collection of Achievements this user has unlocked, most recently unlocked first."

      field :feed_posts, Connections.define(Objects::FeedPost), "Feed posts owned by the user", null: false, visibility: :internal

      def feed_posts
        ArrayWrapper.new([])
      end

      field :all_projects_v2, Connections.define(Objects::ProjectV2),
        required_capabilities: [:mobile_only_schema_mask],
        minimum_accepted_scopes: ["read:project"],
        description: "List of all the projects accessible to this user",
        numeric_pagination_enabled: true,
        null: false do
          argument :query, String, "Query to search for projects", required: false
          argument :order_by, Inputs::ProjectV2Order, "How to order the returned projects.", required: false, default_value: { field: "number", direction: "DESC" }
          argument :min_permission_level, Enums::ProjectV2PermissionLevel, "Filter projects based on user role.", required: false, default_value: "read"
          argument :use_full_term_query, Boolean, "Search project titles that match the entire query string", required: false, default_value: false, visibility: :internal
        end

      def all_projects_v2(order_by:, min_permission_level:, query: "", use_full_term_query: false)
        # `null` is considered a valid query value from the GraphQL runtime here, and is converted into `nil`.
        # We need to convert this into a valid String value to pass through to the loader below.
        query = query || ""

        Loaders::AllProjectsV2.load(object, @context[:viewer], query, min_permission_level, use_full_term_query).then do |projects|
          next ArrayWrapper.new(projects) if order_by.nil?

          sort_projects_v2(projects, order_by, query, @context[:viewer])
        end
      end

      field :user_view_type, Platform::Enums::UserViewType, "Whether the request returns publicly visible information or privately visible information about the user", null: false, resolver_method: :user_view_type

      def user_view_type
        is_viewer ? "private" : "public"
      end

      field :enterprise_managed_enterprise_id, String, "The global ID of the enterprise managing the user, if present", null: true, visibility: :internal

      def enterprise_managed_enterprise_id
        business = object.enterprise_managed_business
        return unless business

        GitHub.enterprise? ? business.global_relay_id : business.next_global_id
      end

      field :viewer_can_access_copilot_workspace, Boolean, "If the user can access Copilot Workspace", null: false, required_capabilities: [:mobile_only_schema_mask]

      def viewer_can_access_copilot_workspace
        ::FeatureFlag.vexi.enabled?(:copilot_workspace, @context[:viewer], default: false)
      end

      private

      def validate_date_range(date_range, max_interval:, message:)
        start_date = date_range.first
        end_date = date_range.last
        date_interval = (end_date - start_date).abs

        unless date_interval / max_interval <= 1
          raise Errors::Validation, message
        end
      end

      def build_and_validate_contributions_time_range(from: nil, to: nil)
        # We want to return nil in this case so Loaders::ContributionCollector can apply defaults
        # and thereby share instances of the Collector when `from` and `to` are not passed in the
        # query.
        return unless from || to

        time_range = if from && to
          from..to
        elsif from
          from..(from + 1.year)
        elsif to
          (to - 1.year)..to
        end

        # 372 days for Calendar's range of: (to - 1.year).beginning_of_week(:sunday)
        # Then add a day for leap years
        validate_date_range(time_range, max_interval: 373.days,
          message: "The total time spanned by 'from' and 'to' must not exceed 1 year")

        time_range
      end
    end
  end
end
