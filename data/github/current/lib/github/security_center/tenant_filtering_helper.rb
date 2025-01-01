# typed: true
# frozen_string_literal: true

module GitHub
  module SecurityCenter
    module TenantFilteringHelper
      class RepositoryOutOfScopeError < StandardError
        def initialize(feature)
          @feature = feature
        end

        def message
          "Repository present in #{@feature} results does not belong to the tenant"
        end
      end

      class DeletedRepositoryError < StandardError
        def initialize(feature)
          @feature = feature
        end

        def message
          "Deleted repository present in #{@feature} results"
        end
      end

      class IncorrectRepositoryVisibilityError < StandardError
        def initialize(feature)
          @feature = feature
        end

        def message
          "Repository visibility in #{@feature} results is not in the requested visibilities"
        end
      end

      class RequestScopeIncorrectScopeError < StandardError
        def initialize(scope)
          @scope = scope
        end

        def message
          "Received unsupported scope: #{@scope}"
        end
      end

      class RequestScopeEmptyTenantError < StandardError
        def message
          "Tenant is required to construct request scope"
        end
      end

      class RequestScopeIncorrectTenantTypeError < StandardError
        def initialize(scope, tenant)
          @scope = scope
          @tenant = tenant
        end

        def message
          "Incorrect tenant type passed: scope #{@scope} with tenant #{@tenant.class.name}"
        end
      end

      class RequestScope
        attr_reader :scope, :tenant, :feature

        def initialize(scope, tenant, feature)
          if !tenant.present?
            raise RequestScopeEmptyTenantError
          end

          if (scope == :repository && !tenant.is_a?(Repository)) ||
            (scope == :organization && !tenant.is_a?(Organization)) ||
            (scope == :business && !tenant.is_a?(Business))

            raise RequestScopeIncorrectTenantTypeError.new(scope, tenant)
          end

          if ![:repository, :organization, :business].include?(scope)
            raise RequestScopeIncorrectScopeError.new(scope)
          end

          @scope = scope
          @tenant = tenant
          @feature = feature
        end

        def is_repo?
          @scope == :repository
        end

        def is_org?
          @scope == :organization
        end

        def is_business?
          @scope == :business
        end
      end

      def filter_tenant_rows(scope, rows, repository_id_getter, repo_visibilities = Repository::VISIBILITIES)
        GitHub.dogstats.distribution_time("security_center.tenant_filtering.dist", tags: ["scope:#{scope.scope}", "feature:#{scope.feature}"]) do
          repo_visibilities_set = repo_visibilities.compact.to_set
          repo_ids = rows.map { |r| repository_id_getter.call(r) }.uniq

          if scope.is_repo?
            repos_by_id = [scope.tenant].index_by(&:id)
          elsif scope.is_org?
            repos_by_id = Repository.where(id: repo_ids, owner_id: scope.tenant.id).includes(:internal_repository).index_by(&:id)
          elsif scope.is_business?
            include_emus = ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(scope.tenant).security_center_for_emus_enabled?
            business_organization_ids = scope.tenant.organization_ids.to_set
            # This adds retrieval of repo.owner (from "users" table), which is can later be used for rendering the rows
            # Because the business may have a large number of organizations, wait to perform that filter in-memory, not on the SQL query.
            # The query is still bound by `repo_ids`, which represents the current page of data.
            repos_by_id = Repository.where(id: repo_ids)
            .includes(:mirror, :owner, :internal_repository)
            .select do |repo|
              next false if repo.owner.nil?

              if repo.owner.organization?
                business_organization_ids.include?(repo.owner_id)
              elsif repo.owner.user?
                include_emus
              end
            end.index_by(&:id)
          end

          [rows.select do |r|
            repository_id = repository_id_getter.call(r)
            repo = repos_by_id[repository_id]

            violation, error, additional_report_data = if repo.blank?
              [
                "repository_out_of_scope",
                RepositoryOutOfScopeError.new(scope.feature),
                {}
              ]
            elsif !scope.is_repo? && repo.deleted?
              # If the repository was deleted "recently", we want to filter but not raise telemetry noise
              next false if repository_deleted_recently?(repo)

              # A repo can be deleted before it is fully created.
              # In that case, it is expected that repo.deleted_at can be nil
              [
                "deleted_repository",
                DeletedRepositoryError.new(scope.feature),
                { "gh.repo.deleted_at": repo.deleted_at&.utc }
              ]
            elsif !repo_visibilities_set.include?(repo.visibility)
              [
                "incorrect_repository_visibility",
                IncorrectRepositoryVisibilityError.new(scope.feature),
                { "gh.repo.visibility": repo.visibility }
              ]
            else
              [nil, nil, {}]
            end

            if violation
              GitHub.dogstats.increment(
                "security_center.access_violation",
                tags: [
                  "feature:#{scope.feature}",
                  "scope:#{scope.scope}",
                  "violation:#{violation}"
                ]
              )

              if error
                tenant_props = case scope.tenant
                when Business
                  {
                    "gh.business.id": scope.tenant&.id,
                    "gh.business.name": scope.tenant&.name,
                  }
                when Organization
                  {
                    "gh.org.id": scope.tenant&.id,
                    "gh.org.login": scope.tenant&.display_login,
                  }
                when Repository
                  {
                    "gh.repo.id": scope.tenant&.id,
                    "gh.repo.name_with_owner": scope.tenant&.name_with_display_owner,
                  }
                else
                  {}
                end

                Failbot.report(
                  error,
                  **tenant_props,
                  "gh.security_center.filtering.out_of_scope_repo_id": repository_id,
                  "gh.security_center.filtering.scope": scope.scope,
                  "gh.security_center.filtering.feature": scope.feature,
                  "gh.security_center.filtering.visibilities": repo_visibilities_set.to_a,
                  **additional_report_data,
                )
              end

              next false
            end

            true
          end, repos_by_id]
        end
      end

      private

      def repository_deleted_recently?(repository)
        return false unless repository.deleted?
        return false if repository.deleted_at.nil?

        repository.deleted_at > 5.minutes.ago
      end
    end
  end
end
