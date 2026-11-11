# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RestrictActionsActorsRule < BulkRunnableRule

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
          description: "Select the actors who can run Actions workflows.", default_value: []))

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
        rule_configs_by_action.flat_map do |action, rule_configs|
          rule_configs.map { |rc| RuleRun.success(rule_config: rc, event_action: action) }
        end
      end

      sig { override.params(rule_config: IRuleConfig).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def ruleset_ui_metadata(rule_config)
        node_ids = rule_config.param("allowed_actors").to_a

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
        actors.concat(IntegrationInstallation.where(id: ids_by_type["IntegrationInstallation"]).to_a) if ids_by_type["IntegrationInstallation"]

        actors = actors.reduce({}) do |acc, actor|
          acc[actor.global_relay_id] = actor_to_json(actor)
          acc
        end
        { actors: actors }
      end

      sig { override.params(source: Types::RuleSource, user: User, query: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def query_ui_metadata(source, user, query)
        if query.start_with?("actor_suggestions:")
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
            suggestions.filter do |actor|
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
          elsif source.is_a?(Organization)
            autocomplete_query = AutocompleteQuery.new(user, filter,
              organization: source,
              include_teams: true,
              include_integration_installations: true)
            autocomplete_query.suggestions
          else
            []
          end
          { actors: actors.map { |u| actor_to_json(u) } }
        else
          {}
        end
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:organization, :repository]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:actions]
      end

      private

      sig { params(actor: T.any(User, Team, IntegrationInstallation)).returns(T::Hash[T.untyped, T.untyped]) }
      def actor_to_json(actor)
        actor = actor.is_a?(IntegrationInstallation) ? actor.integration : actor
        return {} unless actor
        {
          type: actor.class.name,
          avatarUrl: actor.primary_avatar_url,
          globalRelayId: actor.global_relay_id,
          name: actor.is_a?(User) ? actor.display_login : actor.name,
        }
      end
    end
  end
end
