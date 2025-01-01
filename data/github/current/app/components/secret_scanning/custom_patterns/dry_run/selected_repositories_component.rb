# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class SelectedRepositoriesComponent < ApplicationComponent
        include GitHub::SecurityCenter::TenantFilteringHelper

        attr_reader :custom_pattern_owner, :selected_repo_ids

        def initialize(
          custom_pattern_owner:,
          selected_repo_ids:
        )
          @custom_pattern_owner = custom_pattern_owner
          @selected_repo_ids = selected_repo_ids
        end

        def selected_repositories_count_text
          "#{selected_repositories_count} of #{GitHub.secret_scanning_max_dry_run_selected_repositories} repositories selected"
        end

        def selected_repositories_count
          selected_repositories.length
        end

        def clear_all_selected_repositories_button_disabled?
          selected_repositories_count == 0
        end

        memoize def selected_repositories
          ActiveRecord::Base.connected_to(role: :reading) do
            return [] if @selected_repo_ids.blank?
            org_ids = []
            org_ids = @custom_pattern_owner.organization_ids if @custom_pattern_owner.is_a?(Business)
            org_ids = [@custom_pattern_owner.id] if @custom_pattern_owner.is_a?(Organization)

            repos = Repository.where(id: @selected_repo_ids)
            repos, _ = filter_tenant_rows(
              tenant_filter_scope,
              repos,
              -> (repo) { repo.id }
            )

            repos.sort_by(&:name)
          end
        end

        def update_selected_repositories_path
          return settings_org_security_analysis_dry_run_update_selected_repositories_path(@custom_pattern_owner) if @custom_pattern_owner.is_a?(Organization)
          return settings_business_dry_run_update_selected_repositories_enterprise_path(@custom_pattern_owner) if @custom_pattern_owner.is_a?(Business)
        end

        def tenant_filter_scope
          scope = if @custom_pattern_owner.is_a?(Organization)
            :organization
          elsif @custom_pattern_owner.is_a?(Business)
            :business
          end

          GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(
            scope,
            @custom_pattern_owner,
            SecurityCenter::SecurityFeatures::SECRET_SCANNING,
          )
        end
      end
    end
  end
end
