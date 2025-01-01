# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module Projects
      class Backend

        FeatureFlagActor = T.type_alias { T.nilable(T.any(MemexProject, User)) }

        # Controls access to Elasticsearch-backed GraphQL via consumer-specific feature flag.
        # This is in addition to Memex Without Limits feature flags.
        class ConsumerFeatureFlag < T::Enum
          enums do
            # Internal mobile client use only, feature_flag :memex_graphql_elasticsearch_backend
            Mobile = new(:memex_graphql_elasticsearch_backend)
            # Public ProjectsV2Items GraphQL for Memex Without Limits, feature_flag :memex_mwl_graphql
            Public = new(:memex_mwl_graphql)
            # No additional feature flag required
            None = new(:none)
          end
        end

        class << self

          # Run through the required feature flags and ensure the environment, project, and user
          # can and should be using the new Elasticsearch-backed implementation.
          # In addition to Memex Without Limits feature flags, consuming code can specify its own.
          sig do
            params(
              memex_project_or_view: T.any(MemexProject, MemexProjectView),
              feature_flag_actor:  FeatureFlagActor,
              consumer_feature_flag: ConsumerFeatureFlag,
            ).returns(Promise[T::Boolean])
          end
          def async_use_elasticsearch?(memex_project_or_view:, feature_flag_actor:, consumer_feature_flag:)
            feature_flag = consumer_feature_flag == ConsumerFeatureFlag::None ? nil : consumer_feature_flag.serialize
            if memex_project_or_view.is_a?(MemexProject)
              memex_project_or_view.async_owner.then do |owner|
                use_elasticsearch?(memex_project_or_view, owner, feature_flag_actor, feature_flag)
              end
            else
              memex_project_or_view.async_memex_project.then do |memex_project|
                T.must(memex_project).async_owner.then do |owner|
                  use_elasticsearch?(T.must(memex_project), owner, feature_flag_actor, feature_flag)
                end
              end
            end
          end

          private

          sig do
            params(memex_project: MemexProject, owner: T.nilable(User), feature_flag_actor: FeatureFlagActor, feature_flag: T.nilable(Symbol))
            .returns(T::Boolean)
          end
          def use_elasticsearch?(memex_project, owner, feature_flag_actor, feature_flag)
            return false if GitHub.flipper[:memex_without_limits_kill_switch].enabled?

            if owner&.feature_enabled?(:memex_project_without_limits_public_beta, memoize: false)
              !memex_project.feature_enabled?(:memex_table_without_limits_disabled, memoize: false)
            else
              (memex_project.feature_enabled?(:memex_table_without_limits, memoize: false) &&
                (feature_flag.present? ? !!feature_flag_actor&.feature_enabled?(feature_flag) : true))
            end
          end
        end
      end
    end
  end
end
