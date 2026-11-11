# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # Assigns a documentation category to a GraphQL type for use by
      # docs.github.com. Categories align with the REST API reference
      # sections so the GraphQL reference can be split into feature-based
      # pages instead of one massive per-kind page.
      #
      # The category surfaces as a `@docsCategory(name: "<slug>")` directive
      # on the type in `schema.docs.graphql`. Internal and public schema
      # dumps are not affected.
      #
      # Annotation is optional. Types without `docs_category` simply do
      # not emit the directive and end up in the "other" bucket on
      # docs.github.com.
      #
      # Tracking issue: https://github.com/github/docs-engineering/issues/5921
      #
      # Usage:
      #   class Issue < Platform::Objects::Base
      #     docs_category :issues
      #     description "An Issue is a place to discuss…"
      #     # …
      #   end
      #
      # The DSL is also available on Platform::Interfaces::Base,
      # Platform::Unions::Base, Platform::Enums::Base, Platform::Inputs::Base,
      # and Platform::Mutations::Base. On mutations, the directive emits on
      # the corresponding field of the Mutation root type rather than on a
      # type, since GraphQL mutations are fields not types.
      module DocsCategory
        # Allowlist of category symbols. Underscores are converted to dashes
        # when emitted in the directive (e.g. :enterprise_admin -> "enterprise-admin")
        # so slugs match the corresponding REST API category directories under
        # `content/rest/` in github/docs-internal.
        VALID_CATEGORIES = T.let(%i[
          actions
          activity
          apps
          audit_log
          billing
          branches
          checks
          code_scanning
          code_security
          codespaces
          collaborators
          commits
          copilot
          dependabot
          dependency_graph
          deploy_keys
          deployments
          discussions
          enterprise_admin
          gists
          git
          interactions
          issues
          licenses
          meta
          migrations
          orgs
          packages
          pages
          projects
          projects_classic
          pulls
          reactions
          releases
          repos
          scim
          search
          secret_scanning
          security_advisories
          sponsors
          teams
          users
        ].freeze, T::Array[Symbol])

        extend T::Helpers
        requires_ancestor { Module }

        sig { params(category: T.nilable(Symbol)).returns(T.nilable(Symbol)) }
        def docs_category(category = nil)
          if category
            unless VALID_CATEGORIES.include?(category)
              raise ArgumentError, # rubocop:disable GitHub/UsePlatformErrors
                "Invalid docs_category #{category.inspect} for #{name}. " \
                "Valid categories: #{VALID_CATEGORIES.map(&:inspect).join(", ")}"
            end
            @docs_category = T.let(category, T.nilable(Symbol))
          end
          @docs_category
        end
      end
    end
  end
end
