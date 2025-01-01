# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      module DependenciesValueHelpers
        DEPENDENCIES_FIELDS = %w[blocked-by blocking]

        sig { params(context: Search::Memex::Context).returns(T::Boolean) }
        def dependencies_search_enabled?(context)
          # Check for the dependency feature as well so we don't overwrite user queries
          # until dependencies release
          IssueDependenciesFeature.enabled?(context.memex_project.owner)
        end

        sig { params(slug: Symbol, query_value: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def compile_dependencies_value_query(slug:, query_value:)
          nwo_reference_field = value_to_nwo_reference_field(slug.to_s)
          return unless nwo_reference_field

          { term: { nwo_reference_field => { value: query_value } } }
        end

        sig { params(query_value: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def compile_dependencies_existence_query(query_value:)
          id_field = value_to_id_field(query_value)
          return unless id_field

          { exists: { field: id_field } }
        end

        sig { params(query_value: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def compile_dependencies_state_query(query_value:)
          open_count_field = value_to_open_count_field(query_value)
          return unless open_count_field

          {
            bool: {
              must: [
                { term: { "content.state" => { value: "open" } } },
                { range: { open_count_field => { gt: 0 } } },
                { exists: { field: open_count_field } },
              ]
            }
          }
        end

        sig { params(value: String).returns(T.nilable(IssueDependency::DependencyType)) }
        def value_to_dependency_type(value)
          case value
          when "blocked-by", "blocked"
            IssueDependency::DependencyType::BlockedBy
          when "blocking"
            IssueDependency::DependencyType::Blocking
          end
        end

        sig { params(value: String).returns(T.nilable(String)) }
        private def value_to_nwo_reference_field(value)
          type = value_to_dependency_type(value)
          case type
          when IssueDependency::DependencyType::BlockedBy
            "content.blocked_by.nwo_reference.keyword"
          when IssueDependency::DependencyType::Blocking
            "content.blocking.nwo_reference.keyword"
          end
        end

        sig { params(value: String).returns(T.nilable(String)) }
        private def value_to_id_field(value)
          type = value_to_dependency_type(value)
          case type
          when IssueDependency::DependencyType::BlockedBy
            "content.blocked_by.id"
          when IssueDependency::DependencyType::Blocking
            "content.blocking.id"
          end
        end

        sig { params(value: String).returns(T.nilable(String)) }
        private def value_to_open_count_field(value)
          type = value_to_dependency_type(value)
          case type
          when IssueDependency::DependencyType::BlockedBy
            "content.open_blocked_by_count"
          when IssueDependency::DependencyType::Blocking
            "content.open_blocking_count"
          end
        end
      end
    end
  end
end
