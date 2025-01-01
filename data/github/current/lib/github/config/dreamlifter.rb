# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Dreamlifter
      # Public: The GitHub App (Integration) that AzurePipelines uses.
      def azure_pipelines_github_app
        @azure_pipelines_github_app ||= Integration.find_by(slug: azure_pipelines_github_app_slug)
      end

      def azure_pipelines_github_app_name
        "Azure Pipelines"
      end

      def azure_pipelines_github_app_slug
        "azure-pipelines"
      end
    end
  end

  extend Config::Dreamlifter
end
