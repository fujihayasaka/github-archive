# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module Projects
      module Filterable

        # Helper method which knows how to properly concatenate the view's filter and user input query value.
        # Our existing iOS and Android applications rely on this being additive. Basically, the view loads based
        # on the view's saved filter value and then the user has the option to further refine this by adding
        # on additional query value. Ultimately this method helps merge the two together and can then be shared
        # across backend implelementations until the InMemoryBackend is removed once all projects have been
        # converted to the new Elasticsearch-backed implementation.
        sig { params(memex_project_view: MemexProjectView, query: String).returns(String) }
        def derive_query(memex_project_view:, query: "")
          queries = []

          queries << memex_project_view.filter if memex_project_view.filter.present?
          queries << query if query.present?

          queries.join(" ")
        end
      end
    end
  end
end
