# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module IntegrationInstallation
      class RepositoryForViewer < Platform::Loader
        def self.load(repository, viewer, is_assignable = false)
          self.for(viewer, is_assignable).load(repository)
        end

        def initialize(viewer, is_assignable)
          @viewer = viewer
          @is_assignable = is_assignable
        end

        def fetch(repositories)
          repository_ids = repositories.map(&:id)
          for_user = ::IntegrationInstallation.with_user(viewer, repository_ids: repository_ids)

          if viewer&.feature_flag_enabled_or_raise?(:preventing_exception_app_installations) || @is_assignable # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            installations_by_repo = repositories.map { |repository| [repository, for_user.with_repository(repository)] }.to_h

            promises = installations_by_repo.map do |repository, installations|
              filtered = installations

              Promise.all(installations.map(&:async_integration)).then do
                # filtering out the nil integrations if FF is on
                if viewer&.feature_flag_enabled_or_raise?(:preventing_exception_app_installations) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                  filtered = installations.select { |inst| inst.integration.present? }
                end

                if @is_assignable
                  # Filter to only assignable agentic apps that are enabled for this repository
                  enabled_agents = AgenticApp.enabled_for_repository(repository, viewer).select(&:assignable?)
                  enabled_integration_ids = enabled_agents.map { |agent| agent.integration&.id }.compact

                  filtered = filtered.select do |installation|
                    installation.integration.present? && enabled_integration_ids.include?(installation.integration.id)
                  end
                end

                [repository, filtered]
              end
            end

            filtered_results = Promise.all(promises).sync
            filtered_results.to_h
          else
            repositories.map { |repository| [repository, for_user.with_repository(repository)] }.to_h
          end
        end

        private

        attr_reader :viewer
      end
    end
  end
end
