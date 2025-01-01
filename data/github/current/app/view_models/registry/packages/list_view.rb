# typed: true
# frozen_string_literal: true

module Registry
  module Packages
    class ListView
      include UrlHelpers

      attr_accessor :owner, :phrase

      def initialize(owner:, params:)
        # owner is the namespace (an org, repo, or user)
        @owner = owner
        @params = params
        @phrase ||= params.fetch(:q, "")
      end

      def user_or_org
        if owner.is_a?(Repository)
          owner.owner
        else
          owner
        end
      end

      def data_results_container
        if owner.is_a?(Organization)
          "org-packages"
        elsif owner.is_a?(Repository)
          "repo-packages"
        else
          "user-packages-list"
        end
      end

      def search_packages_path(filters: {})
        begin
          query = @params
            .slice(:q, :ecosystem, :visibility, :sort_by)
            .permit(:q, :ecosystem, :visibility, :sort_by)
        rescue ActionController::UnpermittedParameters => e
          query = {}
        end

        query.merge!(filters)

        if owner.is_a?(Organization)
          org_packages_path(owner, query)
        elsif owner.is_a?(Repository)
          packages_path(owner.owner, owner, query)
        else
          user_path(owner, query.merge({ tab: "packages" }))
        end
      end
    end
  end
end
