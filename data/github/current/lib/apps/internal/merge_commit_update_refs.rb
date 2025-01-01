# typed: strict
# frozen_string_literal: true

module Apps
  class Internal
    class MergeCommitUpdateRefs
      extend T::Sig

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.id_finder
        ->() {
          Integration.find_by(
            owner_id: GitHub.trusted_apps_owner_id,
            slug: GitHub.merge_commit_update_refs_github_app_slug,
          )&.id
        }
      end


      PRODUCTION = T.let({
        alias: :merge_commit_update_refs,
        id: id_finder,
        inherits: [:internal],
        capabilities: {
          user_installable: false,
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/pull-requests"],
      }, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String]))

      PERMISSIONS = T.let({}, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integer)) }
      def self.id
        return @merge_commit_update_refs_id if defined?(@merge_commit_update_refs_id)
        @merge_commit_update_refs_id = T.let(Apps::Internal.integration_id(:merge_commit_update_refs), T.nilable(Integer))
      end

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Internal.integration(:merge_commit_update_refs).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: GitHub.merge_commit_update_refs_github_app_name,
          slug: GitHub.merge_commit_update_refs_github_app_slug,
          url: "https://github.com/",
          public: true,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        app = Integration.create!(integration_attributes)

        app
      end
    end
  end
end
