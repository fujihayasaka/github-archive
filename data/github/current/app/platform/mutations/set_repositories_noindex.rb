# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetRepositoriesNoindex < Platform::Mutations::Base
      docs_category :repos
      description "Set or clear the noindex flag on repositories to control external search engine indexing"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_ids, [ID], "The global relay ids of repositories to update.", required: true, loads: Objects::Repository, as: :repositories
      argument :noindex, Boolean, "Whether to enable or disable noindex.", required: true

      field :repositories, [Objects::Repository], "The updated repositories.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(repositories:, noindex:, **inputs)
        repositories.each do |repository|
          unless repository.public?
            raise Errors::Validation.new "Network privileges can only be set on public repositories: #{repository.name_with_display_owner}"
          end

          repository.set_network_privilege(:noindex, noindex, actor: context[:viewer])
        end

        { repositories: repositories }
      end
    end
  end
end
