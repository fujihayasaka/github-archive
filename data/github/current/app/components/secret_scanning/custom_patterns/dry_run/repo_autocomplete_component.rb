# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class RepoAutocompleteComponent < ApplicationComponent
        attr_reader :custom_pattern_owner, :selected_repo_ids

        def initialize(
          custom_pattern_owner:,
          selected_repo_ids:
        )
          @custom_pattern_owner = custom_pattern_owner
          @selected_repo_ids = selected_repo_ids
        end

        def placeholder_text
          "Search by repository name"
        end

        def repository_suggestions_path
          return settings_org_security_analysis_dry_run_repository_suggestions_path(@custom_pattern_owner) if @custom_pattern_owner.is_a?(Organization)
          settings_business_dry_run_repository_suggestions_enterprise_path(@custom_pattern_owner) if @custom_pattern_owner.is_a?(Business)
        end

        def update_selected_repositories_path
          return settings_org_security_analysis_dry_run_update_selected_repositories_path(@custom_pattern_owner) if @custom_pattern_owner.is_a?(Organization)
          settings_business_dry_run_update_selected_repositories_enterprise_path(@custom_pattern_owner) if @custom_pattern_owner.is_a?(Business)
        end
      end
    end
  end
end
