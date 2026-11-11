# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RestrictActionsActorsRule < BulkRunnableRule
      # Actor categories for improved targeting in the allowed-actors picker UI.
      # Category names may be pluralized in some display contexts.
      ACTOR_CATEGORIES = T.let({
        user: "User",
        role: "Role",
        team: "Team",
        ai: "AI",
        automation: "Automation",
      }.freeze, T::Hash[Symbol, String])

      # Query value (sent as `query` on the rule's query_ui_metadata endpoint) that asks for
      # the list of actor categories rather than for a list of actors.
      ACTOR_CATEGORIES_QUERY = "actor_categories"

      # Maximum number of allowed-actor entries a single rule configuration may hold.
      # Enforced at save time via the schema's `max_elements`, and re-applied defensively at
      # evaluation time so legacy/oversized configurations can't blow past the bound. Caps
      # the size of the IN-clauses we issue against `abilities` and `user_roles` on the
      # workflow-run hot path. 100 comfortably covers realistic configurations (typical ones
      # hold a handful of teams/apps/roles).
      MAX_ALLOWED_ACTORS = 100

      # Per-evaluation cache of `Repository#permissions_hash_for` results, keyed by
      # `[user_id, repository_id]`. The value shape mirrors `Repository.permissions_hash`:
      # `{ admin:, maintain:, push:, triage:, pull: }`.
      PermissionsCache = T.type_alias { T::Hash[[Integer, Integer], T::Hash[Symbol, T::Boolean]] }

      # Per-evaluation cache of team-membership lookups, keyed by `[user_id, team_ids]` where
      # `team_ids` is the sorted, deduped list of allowed team ids the membership was checked
      # against. Identical to `PermissionsCache` in lifetime: created fresh per `run_evaluation`
      # call, never instance-scoped.
      TeamMembershipCache = T.type_alias { T::Hash[[Integer, T::Array[Integer]], T::Boolean] }

      # Per-evaluation cache of role-membership lookups, keyed by
      # `[user_id, repository_id, role_ids]` where `role_ids` is sorted+deduped. Same lifetime
      # rules as the other caches.
      RoleMembershipCache = T.type_alias { T::Hash[[Integer, Integer, T::Array[Integer]], T::Boolean] }

      # Bundles the per-evaluation caches threaded through `evaluate_workflow_run`. Grouped into
      # one struct so adding future caches doesn't churn every call site's signature.
      class EvaluationCaches < T::Struct
        prop :permissions, PermissionsCache, default: {}
        prop :team_membership, TeamMembershipCache, default: {}
        prop :role_membership, RoleMembershipCache, default: {}
      end

      # Serialized representation of an allowed-actor entry sent to the picker UI.
      # `actor_category` is `nil` when the `:ruleset_actor_categories` feature flag is disabled.
      # `preferred_avatar_url` and `owner` are only populated for actor types that have them.
      class ActorPayload < T::Struct
        const :actor_type, String
        const :actor_category, T.nilable(String)
        const :preferred_avatar_url, T.nilable(String)
        const :global_relay_id, String
        const :name, String
        const :owner, T.nilable(String)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            actorType: actor_type,
            actorCategory: actor_category,
            preferredAvatarUrl: preferred_avatar_url,
            globalRelayId: global_relay_id,
            name:,
            owner:,
          }
        end
      end

      sig { void }
      def initialize
        super(rule_name: "restrict_actions_actors",
              display_name: "Restrict actors",
              description: "Choose specific actors that are authorized to trigger Actions workflows.",
              feature_flag: :actions_rulesets)
      end

      sig { override.params(source: T.nilable(Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(T::Boolean) }
      def generate_api
        false
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })
        schema.add_field(ParameterSchema::Array.new(name: "allowed_actors", display_name: "Allowed actors",
          content_type: :node_id, required: true, ui_control: "actor_selector",
          description: "Select the actors who can run Actions workflows.", default_value: [],
          max_elements: MAX_ALLOWED_ACTORS))

        schema
      end

      sig do
        override.params(
          event: RuleEvent,
          rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[IRuleConfig]]
        )
        .returns(T::Array[RuleRun])
      end
      def run_evaluation(event, rule_configs_by_action)
        # Per-evaluation caches shared across all actions/rule_configs in this call. Scoping
        # them to a single `run_evaluation` invocation avoids serving stale data across
        # evaluations (the rule instance is a long-lived singleton on `Evaluator`) while still
        # collapsing repeated `(user, repo)` / `(user, team_ids)` lookups within one event.
        caches = EvaluationCaches.new

        rule_configs_by_action.flat_map do |action, rule_configs|
          rule_configs.map do |rc|
            if action.is_a?(ActionsRules::EventActionWorkflowRun)
              evaluate_workflow_run(action, rc, caches)
            else
              RuleRun.success(rule_config: rc, event_action: action)
            end
          end
        end
      end

      sig do
        params(
          action: ActionsRules::EventActionWorkflowRun,
          rule_config: IRuleConfig,
          caches: EvaluationCaches,
        ).returns(RuleRun)
      end
      def evaluate_workflow_run(action, rule_config, caches = EvaluationCaches.new)
        allowed_actors = rule_config.param("allowed_actors").to_a.first(MAX_ALLOWED_ACTORS)

        actor = action.triggering_actor
        actor_global_id = actor.global_relay_id

        if allowed_actors.include?(actor_global_id)
          return RuleRun.success(rule_config: rule_config, event_action: action)
        end

        # Check team membership. Honors team hierarchy: a member of a child team inherits the
        # allow-listed parent team. We use `Team.member_of?` (with `immediate_only: false` to
        # expand descendants and `with_business_teams: true` to include cross-org BusinessTeams)
        # rather than `user.teams(...)`, which routes through a Promise loader and can cache
        # stale results across promise contexts in tests.
        team_ids = resolve_ids_by_type(allowed_actors, "Team")
        if team_ids.any? && user_in_any_team?(actor, team_ids, caches)
          return RuleRun.success(rule_config: rule_config, event_action: action)
        end

        # Check integration (GitHub App) allowlisting.
        # `triggering_integration` is an IntegrationInstallation; allow matching against either
        # the installation's global id (selected via the standard app picker) or the underlying
        # Integration's global id. The latter only applies to Copilot integrations today: those
        # are surfaced via the global picker as a single Integration regardless of installation,
        # so we intentionally restrict the cross-installation match to that case to avoid
        # accidentally broadening other apps to all of their installations.
        if (installation = action.triggering_integration)
          if allowed_actors.include?(installation.global_relay_id)
            return RuleRun.success(rule_config: rule_config, event_action: action)
          end

          integration = installation.integration
          if integration && copilot_integration?(integration) && allowed_actors.include?(integration.global_relay_id)
            return RuleRun.success(rule_config: rule_config, event_action: action)
          end
        end

        # Check repository role membership
        role_ids = resolve_ids_by_type(allowed_actors, "RepositoryRole")
        if role_ids.any? && user_has_any_role?(actor, action.repository, role_ids, caches)
          return RuleRun.success(rule_config: rule_config, event_action: action)
        end

        RuleRun.failure(
          rule_config: rule_config,
          event_action: action,
          message: "Actor is not allowed to trigger Actions workflows.",
        )
      rescue ActiveRecord::QueryAborted => e
        # Fail closed on DB timeouts / connection failures: this rule restricts who can run
        # Actions, so an indeterminate evaluation should deny rather than silently allow.
        # Surfacing as a `RuleRun.failure` (not a raised exception) keeps a single slow query
        # from breaking the entire workflow-run evaluation pipeline.
        Failbot.report(e, app: "github", rule: rule_name, repository_id: action.repository.id)
        RuleRun.failure(
          rule_config: rule_config,
          event_action: action,
          message: "Could not evaluate allowed actor restrictions; failing closed.",
        )
      end

      # Memoized wrapper around `Team.member_of?`. See `EvaluationCaches` for cache lifetime.
      # Sorts+dedupes `team_ids` so callers passing the same set in a different order still
      # share a cache slot.
      sig do
        params(
          user: User,
          team_ids: T::Array[Integer],
          caches: EvaluationCaches,
        ).returns(T::Boolean)
      end
      def user_in_any_team?(user, team_ids, caches)
        key = [user.id, team_ids.uniq.sort]
        cached = caches.team_membership[key]
        return cached unless cached.nil?

        result = Team.member_of?(team_ids, user.id, immediate_only: false, with_business_teams: true)
        caches.team_membership[key] = result
        result
      end

      sig { params(node_ids: T::Array[String], type_name: String).returns(T::Array[Integer]) }
      def resolve_ids_by_type(node_ids, type_name)
        node_ids.filter_map do |node_id|
          type, id = Platform::Helpers::NodeIdentification.from_global_id(node_id)
          id if type == type_name
        rescue Platform::Errors::NotFound
          nil
        end
      end

      # Returns true when `user` holds any of the supplied repository roles on `repository`,
      # either directly, via a built-in role inheritance, or via a custom role assignment
      # (directly or through a team).
      sig do
        params(
          user: User,
          repository: Repository,
          role_ids: T::Array[Integer],
          caches: EvaluationCaches,
        ).returns(T::Boolean)
      end
      def user_has_any_role?(user, repository, role_ids, caches = EvaluationCaches.new)
        cache_key = [user.id, repository.id, role_ids.uniq.sort]
        cached = caches.role_membership[cache_key]
        return cached unless cached.nil?

        result = compute_user_has_any_role(user, repository, role_ids, caches)
        caches.role_membership[cache_key] = result
        result
      end

      sig do
        params(
          user: User,
          repository: Repository,
          role_ids: T::Array[Integer],
          caches: EvaluationCaches,
        ).returns(T::Boolean)
      end
      def compute_user_has_any_role(user, repository, role_ids, caches)
        roles = RepositoryRole.where(id: role_ids).to_a
        return false if roles.empty?

        # Use `custom?` rather than name matching so a custom role that happens to share a
        # name with a built-in (e.g., a custom role literally named "write") isn't routed
        # through the built-in permissions hash and silently misclassified.
        builtin_roles, custom_roles = roles.partition { |role| !role.custom? }

        if builtin_roles.any?
          user_permissions = user_permissions_for(user, repository, caches)
          builtin_match = builtin_roles.any? do |role|
            permission_key = Team::ABILITIES_TO_PERMISSIONS[role.name]&.to_sym
            permission_key && user_permissions[permission_key]
          end
          return true if builtin_match
        end

        if custom_roles.any? && repository.in_organization?
          custom_role_ids = custom_roles.map(&:id)

          # Scope the user's teams to this repo's owning org (regular Teams have an
          # organization_id; BusinessTeams have NULL organization_id and are kept so they
          # can match cross-org). Without this scope, users in many orgs would pull every
          # team id they belong to into the IN-clause below.
          team_ids = user.teams(with_business_teams: true)
            .where("teams.organization_id = ? OR teams.organization_id IS NULL", repository.owner_id)
            .pluck(:id)

          query = UserRole.where(role_id: custom_role_ids, target_type: "Repository", target_id: repository.id)
          matched = query.where(actor_type: "User", actor_id: user.id)
            .or(query.where(actor_type: %w[Team BusinessTeam], actor_id: team_ids))
          return true if matched.exists?
        end

        false
      end

      # Memoizes `repository.permissions_hash_for(actor: user)` within a single `run_evaluation`
      # call (cache lives on the threaded `EvaluationCaches`). `run_evaluation` iterates through
      # every action in the event, and several may share the same (user, repo) tuple; without
      # memoization we'd hit the permissions service once per action. Caches are intentionally
      # NOT instance-scoped: the rule object is a long-lived singleton on `Evaluator`, so
      # caching across calls would serve stale authorization data after membership changes.
      sig do
        params(
          user: User,
          repository: Repository,
          caches: EvaluationCaches,
        ).returns(T::Hash[Symbol, T::Boolean])
      end
      def user_permissions_for(user, repository, caches)
        caches.permissions[[user.id, repository.id]] ||= T.cast(
          repository.permissions_hash_for(actor: user),
          T::Hash[Symbol, T::Boolean],
        )
      end

      sig { override.params(rule_config: IRuleConfig).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def ruleset_ui_metadata(rule_config)
        node_ids = rule_config.param("allowed_actors").to_a
        source = rule_config.source

        ids_by_type = node_ids.reduce({}) do |acc, node_id|
          begin
            type, id = Platform::Helpers::NodeIdentification.from_global_id(node_id)
            acc[type] ||= []
            acc[type] << id
            acc
          rescue Platform::Errors::NotFound
            # ignore missing users
            acc
          end
        end
        actors = []
        actors.concat(User.where(id: ids_by_type["User"]).to_a) if ids_by_type["User"]
        actors.concat(Team.where(id: ids_by_type["Team"]).to_a) if ids_by_type["Team"]
        actors.concat(IntegrationInstallation.where(id: ids_by_type["IntegrationInstallation"]).includes(:integration).to_a) if ids_by_type["IntegrationInstallation"]
        actors.concat(Integration.where(id: ids_by_type["App"]).to_a) if ids_by_type["App"]
        actors.concat(RepositoryRole.where(id: ids_by_type["RepositoryRole"]).to_a) if ids_by_type["RepositoryRole"]

        actors = actors.each_with_object({}) do |actor, acc|
          payload = actor_to_json(actor, source)
          acc[actor.global_relay_id] = payload.to_hash if payload
        end
        { actors: actors }
      end

      sig { override.params(source: Types::RuleSource, user: User, query: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def query_ui_metadata(source, user, query)
        if query == ACTOR_CATEGORIES_QUERY
          categories = source.feature_enabled_for_source?(:ruleset_actor_categories) ? ACTOR_CATEGORIES.values : []
          { categories: categories }
        elsif query.start_with?("actor_suggestions:")
          filter = query.sub("actor_suggestions:", "").downcase

          actors = if source.is_a?(Repository)
            autocomplete_query = AutocompleteQuery.new(user, filter,
              organization: source.organization,
              repository: source,
              include_teams: true,
              include_integration_installations: true)
            suggestions = autocomplete_query.suggestions

            write_user_ids = T.let(nil, T.nilable(T::Enumerable[Integer]))
            write_team_ids = T.let(nil, T.nilable(T::Enumerable[Integer]))
            app_team_ids = T.let(nil, T.nilable(T::Enumerable[Integer]))
            filtered_suggestions = suggestions.filter do |actor|
              if actor.instance_of?(Team)
                write_team_ids ||= source.actor_ids(type: Team, min_action: :write)
                (actor.id_and_ancestor_ids & write_team_ids).any?
              elsif actor.instance_of?(User)
                write_user_ids ||= source.actor_ids(type: User, min_action: :write)
                # User owned repositories won't include the owner in the list of users, so explicitly check for that
                (write_user_ids.include?(actor.id)) || (!source.owner&.organization? && (actor.id == source.owner_id))
              elsif actor.instance_of?(IntegrationInstallation)
                app_team_ids ||= begin
                  Authorization.service.actor_ids_with_granular_permissions_on(
                    actor_type: IntegrationInstallation,
                    subject_type: Repository,
                    subject_ids: [source.id],
                    owner_ids: [source.owner_id],
                    permissions: [:contents, :single_file],
                    min_action: :write,
                  )
                end
                app_team_ids.include?(actor.id)
              end
            end

            # Add Copilot integrations and repository roles for parity with org-level rulesets.
            # These are global/org-scoped concepts and aren't filtered by repo write permissions.
            copilot_integrations = copilot_integrations_for_suggestions(source, filter)
            roles = roles_for_suggestions(source, filter)

            # Drop any IntegrationInstallation whose underlying Integration we're already
            # emitting as a raw Integration (Copilot apps), so the dropdown doesn't show
            # the same app twice with two different globalRelayIds.
            copilot_integration_ids = copilot_integrations.map(&:id).to_set
            filtered_suggestions = filtered_suggestions.reject do |actor|
              actor.instance_of?(IntegrationInstallation) && copilot_integration_ids.include?(actor.integration_id)
            end

            filtered_suggestions + copilot_integrations + roles
          elsif source.is_a?(Organization)
            autocomplete_query = AutocompleteQuery.new(user, filter,
              organization: source,
              include_teams: true)
            suggestions = autocomplete_query.suggestions

            # AutocompleteQuery only includes integration installations when a repository is present,
            # so we need to fetch them separately for org-level rulesets. Mirror the
            # `user_installable` filter used by IntegrationBypassActor#suggest_bypassers so we
            # don't surface internal apps that aren't meant to appear in user-facing pickers.
            integration_installations = org_integration_installations_for_filter(source, filter)

            # Add Copilot integrations
            copilot_integrations = copilot_integrations_for_suggestions(source, filter)

            # Add repository roles (write, maintain, admin, and custom roles)
            roles = roles_for_suggestions(source, filter)

            # Drop any IntegrationInstallation whose underlying Integration we're already
            # emitting as a raw Integration (Copilot apps), so the dropdown doesn't show
            # the same app twice with two different globalRelayIds.
            copilot_integration_ids = copilot_integrations.map(&:id).to_set
            integration_installations = integration_installations.to_a.reject do |installation|
              copilot_integration_ids.include?(installation.integration_id)
            end

            suggestions + integration_installations + copilot_integrations + roles
          else
            []
          end
          { actors: actors.filter_map { |u| actor_to_json(u, source)&.to_hash } }
        else
          {}
        end
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:business, :organization, :repository]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:actions]
      end

      private

      # Returns nil when the actor cannot be rendered (e.g., an IntegrationInstallation whose
      # underlying Integration has been deleted). Callers must filter nils out so we don't
      # render an empty entry in the picker.
      sig { params(actor: T.any(User, Team, IntegrationInstallation, Integration, RepositoryRole), source: T.nilable(Types::RuleSource)).returns(T.nilable(ActorPayload)) }
      def actor_to_json(actor, source)
        category = actor_category_for(actor, source)
        display_actor = actor.is_a?(IntegrationInstallation) ? actor.integration : actor
        return nil unless display_actor

        if display_actor.is_a?(RepositoryRole)
          ActorPayload.new(
            actor_type: "RepositoryRole",
            actor_category: category,
            preferred_avatar_url: nil,
            global_relay_id: display_actor.global_relay_id,
            name: role_display_name(display_actor),
            owner: nil,
          )
        else
          # When the input actor is an IntegrationInstallation, emit the installation's
          # global_relay_id (which is what `evaluate_workflow_run` matches against for
          # non-Copilot apps) while still pulling display fields from the underlying
          # Integration. Copilot integrations are surfaced as raw Integration objects via
          # `copilot_integrations_for_suggestions`, so they correctly use the Integration's
          # global_relay_id here.
          global_relay_id = actor.is_a?(IntegrationInstallation) ? actor.global_relay_id : display_actor.global_relay_id

          ActorPayload.new(
            actor_type: T.must(display_actor.class.name),
            actor_category: category,
            preferred_avatar_url: display_actor.primary_avatar_url,
            global_relay_id: global_relay_id,
            name: actor_display_name(display_actor, source),
            owner: display_actor.is_a?(Integration) ? display_actor.owner&.display_login : nil,
          )
        end
      end

      # Copilot integrations render their product name; everything else uses login or name.
      sig { params(display_actor: T.any(User, Team, Integration), source: T.nilable(Types::RuleSource)).returns(String) }
      def actor_display_name(display_actor, source)
        case display_actor
        when User
          display_actor.display_login
        when Integration
          copilot_integration?(display_actor) ? copilot_product_name(display_actor, source) : display_actor.name
        else
          display_actor.name
        end
      end

      # Product-facing name for a Copilot integration, shared by the picker label and filter string.
      sig { params(integration: Integration, source: T.nilable(Types::RuleSource)).returns(String) }
      def copilot_product_name(integration, source)
        case integration.id
        when Apps::Privileged.integration_id(:copilot_swe_agent)
          FeatureFlag.vexi.enabled?(:cca_rename, source, default: false) ? "Copilot Cloud Agent" : "Copilot Coding Agent"
        when Apps::Privileged.integration_id(:copilot_pull_request_reviewer)
          "Copilot Code Review"
        when Apps::Privileged.integration_id(:copilot_cli_github_app)
          "Copilot CLI"
        else
          integration.name
        end
      end

      sig { params(role: RepositoryRole).returns(String) }
      def role_display_name(role)
        case role.name
        when "admin"
          "Repository admin"
        when "write", "maintain", "read", "triage"
          role.name.humanize
        else
          role.name
        end
      end

      sig { params(actor: T.any(User, Team, IntegrationInstallation, Integration, RepositoryRole), source: T.nilable(Types::RuleSource)).returns(T.nilable(String)) }
      def actor_category_for(actor, source)
        return nil unless source&.feature_enabled_for_source?(:ruleset_actor_categories)

        case actor
        when User
          T.must(ACTOR_CATEGORIES[:user])
        when Team
          T.must(ACTOR_CATEGORIES[:team])
        when IntegrationInstallation
          if copilot_integration?(actor.integration)
            T.must(ACTOR_CATEGORIES[:ai])
          else
            T.must(ACTOR_CATEGORIES[:automation])
          end
        when Integration
          if copilot_integration?(actor)
            T.must(ACTOR_CATEGORIES[:ai])
          else
            T.must(ACTOR_CATEGORIES[:automation])
          end
        when RepositoryRole
          T.must(ACTOR_CATEGORIES[:role])
        else
          T.absurd(actor)
        end
      end

      # Accepts the underlying Integration (or nil if the installation has been deleted).
      sig { params(integration: T.nilable(Integration)).returns(T::Boolean) }
      def copilot_integration?(integration)
        return false unless integration

        Apps::Privileged.capable?(:is_copilot, app: integration)
      end

      # Derives picker suggestions from every `is_copilot` app, loading rows fresh so absent apps
      # are skipped and no stale registry-cached records leak in.
      sig { params(source: Types::RuleSource, filter: String).returns(T::Array[Integration]) }
      def copilot_integrations_for_suggestions(source, filter)
        copilot_app_ids = Apps::Privileged.all_ids_with_capability(:is_copilot, type: "Integration")
        copilot_apps = copilot_app_ids.empty? ? [] : Integration.where(id: copilot_app_ids).to_a

        copilot_apps
          .map { |integration| [integration, copilot_product_name(integration, source)] }
          .select { |integration, product_name| integration_matches_filter?(integration, filter, product_name.downcase) }
          .sort_by { |_integration, product_name| product_name }
          .map { |integration, _product_name| integration }
      end

      # An integration matches the filter when the filter is blank, or when the filter is a
      # substring of any of: the canonical display name, the integration's own name, or its slug.
      # Matching against name/slug keeps these in parity with `Integration.name_or_slug_like`,
      # which is what the regular installation search uses.
      sig { params(integration: Integration, filter: String, display_name: String).returns(T::Boolean) }
      def integration_matches_filter?(integration, filter, display_name)
        return true if filter.blank?
        return true if display_name.include?(filter)
        return true if integration.name.to_s.downcase.include?(filter)
        return true if integration.slug.to_s.downcase.include?(filter)

        false
      end

      sig { params(source: Organization, filter: String).returns(T::Array[IntegrationInstallation]) }
      def org_integration_installations_for_filter(source, filter)
        org_installed_integration_ids = IntegrationInstallation.where(target: source).user_installable.pluck(:integration_id)
        matching_integration_ids = Integration.user_installable
          .where(id: org_installed_integration_ids)
          .name_or_slug_like(filter)
          .limit(10)
          .pluck(:id)
        IntegrationInstallation.where(target: source, integration_id: matching_integration_ids)
          .user_installable
          .preload(:integration)
          .limit(10)
          .to_a
      end

      sig { params(source: Types::RuleSource, filter: String).returns(T::Array[RepositoryRole]) }
      def roles_for_suggestions(source, filter)
        roles = T.let([], T::Array[RepositoryRole])

        # Add system repository roles (write, maintain, admin)
        # These methods are defined on Role but return RepositoryRole instances
        system_roles = T.cast(
          [RepositoryRole.write_role, RepositoryRole.maintain_role, RepositoryRole.admin_role],
          T::Array[RepositoryRole]
        )
        system_roles.each do |role|
          display_name = role_display_name(role).downcase
          if filter.blank? || display_name.include?(filter) || role.name.include?(filter)
            roles << role
          end
        end

        # Add custom roles for the organization
        org = source.is_a?(Organization) ? source : source.try(:organization)
        if org.present?
          custom_roles = RepositoryRole.custom_roles_for_org(org)
          custom_roles.each do |role|
            if filter.blank? || role.name.downcase.include?(filter)
              roles << role
            end
          end
        end

        roles
      end
    end
  end
end
