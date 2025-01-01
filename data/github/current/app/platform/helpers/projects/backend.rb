# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module Projects
      class Backend
        class << self

          # Run through the required feature flags and ensure the environment, project, and user
          # can and should be using the new Elasticsearch-backed implementation.
          # In addition to Memex Without Limits feature flags, consuming code can specify its own.
          sig do
            params(
              memex_project_or_view: T.any(MemexProject, MemexProjectView),
            ).returns(Promise[T::Boolean])
          end
          def async_use_elasticsearch?(memex_project_or_view:)
            if memex_project_or_view.is_a?(MemexProject)
              Promise.resolve(use_elasticsearch?(memex_project_or_view))
            else
              memex_project_or_view.async_memex_project.then do |memex_project|
                use_elasticsearch?(T.must(memex_project))
              end
            end
          end

          private

          sig { params(memex_project: MemexProject).returns(T::Boolean) }
          def use_elasticsearch?(memex_project)
            memex_project.memex_table_without_limits_or_pwl_public_beta_enabled?
          end
        end
      end
    end
  end
end
