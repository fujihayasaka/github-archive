# typed: true
# frozen_string_literal: true

require "forwardable"

module Stafftools
  module RepositoryViews
    class PageDeploymentView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      extend Forwardable

      attr_reader :repository, :page_deployment
      def initialize(repository, page_deployment)
        @repository, @page_deployment = repository, page_deployment
      end

      def ==(other)
        return false unless other.is_a?(self.class)
        id == other.id
      end

      def_delegators :page_deployment, :id, :ref_name

      def most_recent_build_time
        most_recent_build = page_deployment&.builds&.first
        return nil unless most_recent_build
        most_recent_build.created_at
      end

      def check_run_id
        page_deployment&.check_run_id
      end

      def storage_servers
        if repository.page && page_deployment
          Page::Deployment.connection.select_values(Arel.sql(<<-SQL, page_deployment_id: page_deployment.id))
            SELECT host FROM pages_replicas
            WHERE pages_deployment_id = :page_deployment_id
          SQL
        else
          [].freeze
        end
      end

      def storage_path
        if repository.page && page_deployment&.revision
          GitHub::Routing.dpages_storage_path(repository.page.id, revision: page_deployment.revision)
        end
      end

      def published_url
        return repository.gh_pages_url.to_s if repository.page.build_type == "workflow" && page_deployment.revision == repository.page.built_revision
        return repository.gh_pages_url.to_s if repository.page.source_branch == ref_name

        page_deployment.preview_url
      end

      # LegacyPageDeploymentView describes a PageDeploymentView that is
      # the "legacy" way, i.e. without a `page_deployment` row. The replicas
      # do not have `pages_replicas.page_deployment_id` populated and the
      # storage path uses the `pages.built_revision` column.
      class LegacyPageDeploymentView
        attr_reader :repository
        def initialize(repository)
          @repository = repository
        end

        def ==(other)
          return false unless other.is_a?(self.class)
          id == other.id &&
            storage_servers == other.storage_servers &&
            storage_path == other.storage_path &&
            ref_name == other.ref_name &&
            most_recent_build_time == other.most_recent_build_time &&
            published_url == other.published_url
        end

        def id
          -1
        end

        def storage_servers
          if repository.page
            Page.connection.select_values(Arel.sql(<<-SQL, page_id: repository.page.id))
              SELECT host FROM pages_replicas
              WHERE page_id = :page_id
              AND pages_deployment_id IS NULL
            SQL
          else
            [].freeze
          end
        end

        def storage_path
          if repository.page && repository.page.built_revision
            GitHub::Routing.dpages_storage_path(repository.page.id, revision: repository.page.built_revision)
          end
        end

        def ref_name
          if repository.page
            repository.page.source_branch
          else
            "".freeze
          end
        end

        def most_recent_build_time
          if repository.page && page_build = repository.page.builds.where(page_deployment_id: nil).first
            page_build.created_at
          end
        end

        def published_url
          repository.gh_pages_url.to_s
        end
      end

    end
  end
end
