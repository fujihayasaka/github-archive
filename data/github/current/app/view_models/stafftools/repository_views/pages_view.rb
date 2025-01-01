# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class PagesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::Sentry

      attr_reader :repository

      PAGES_PROJECT_ID = 1890361
      PAGES_CERTIFICATES_PROJECT_ID = 1890346
      PAGES_USER_PROJECT_ID = 1890362

      def page_title
        "#{repository.name_with_owner} - Pages"
      end

      def show_spam?
        GitHub.spamminess_check_enabled?
      end

      def errors_url
        if Rails.env.production? && !GitHub.enterprise?
          sentry_query_link [PAGES_PROJECT_ID, PAGES_CERTIFICATES_PROJECT_ID, PAGES_USER_PROJECT_ID], "repo_id:#{repository.id}"
        else
          "/devtools/exceptions?app=pages"
        end
      end

      def recent_page_builds
        if repository.page && repository.page.builds.any?
          repository.page.builds.limit(50)
        else
          []
        end
      end

      # The path to a commit in the repository.
      #
      # commit_oid - A string containing the commit oid.
      #
      # Returns a string containing a path to the commit.
      def commit_object(commit_oid)
        begin
          if repository.commits.exist?(commit_oid)
            repository.commits.find(commit_oid)
          end
        rescue RepositoryObjectsCollection::InvalidObjectId
          nil
        end
      end

      # The domain on which the page is published
      #
      # Examples:
      # - jdennes.github.io (no custom domain set up)
      # - example.com (custom domain)
      # - pages.git.apple.internal (on enterprise with subdomain isolation)
      # - git.apple.internal (on enterprise without subdomain isolation)
      #
      # Returns a string containing the domain on which the page is published
      def domain
        if repository.page && repository.page.cname
          repository.page.cname
        else
          subdomain_prefix = "#{repository.owner.to_s.downcase}." unless GitHub.enterprise?
          "#{subdomain_prefix}#{repository.pages_host_name}"
        end
      end

      # The URL at which the page is published
      #
      # Examples:
      # - http://jdennes.github.io (user page)
      # - http://jdennes.github.io/project (project page)
      # - http://example.com (custom domain)
      # - https://pages.git.apple.internal/username (user page on enterprise with subdomain isolation)
      # - https://git.apple.internal/pages/username (user page on enterprise without subdomain isolation)
      # - https://pages.git.apple.internal/username/repo-name (project page on enterprise with subdomain isolation)
      # - https://git.apple.internal/pages/username/repo-name (project page on enterprise without subdomain isolation)
      #
      # Returns a string containing the URL at which the page is published
      def published_url
        if GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.stafftools_tenant? && GitHub.flipper[:stafftools_pages_proxima_published_domain].enabled?
          business = GitHub::CurrentTenant.unscope { repository.owner&.business }
          if business
            return GitHub::CurrentTenant.set(business) do
              repository.gh_pages_url.to_s
            end
          end
        end
        repository.gh_pages_url.to_s
      end

      def deployments
        @deployments ||= ([main_deployment] + preview_deployments)
      end

      def preview_deployments
        if repository.page
          if repository.page.workflow_build_enabled?
            repository.page.deployments
              .where("revision != ?", repository.page.built_revision)
              .order("updated_at DESC")
              .map { |d| PageDeploymentView.new(repository, d) }
          else
            repository.page.deployments
            .where("ref_name != ?", repository.pages_branch)
            .order("updated_at DESC")
            .map { |d| PageDeploymentView.new(repository, d) }
          end
        else
          [].freeze
        end
      end

      def main_deployment
        if repository.page
          if repository.page.workflow_build_enabled?
            deployment = repository.page.deployments.where(revision: repository.page.built_revision).first
          else
            deployment = repository.page.deployment_for(repository.pages_branch)
          end
          return PageDeploymentView.new(repository, deployment) if deployment
        end

        PageDeploymentView::LegacyPageDeploymentView.new(repository)
      end

      def certificate_for_alt_domain?
        repository.page&.certificate&.alt_domain.present?
      end

      def build_type
        return nil unless repository.page
        if repository.page.workflow_build_enabled?
          :workflow
        elsif repository.page.dynamic_workflow_disabled_reason.nil?
          :dynamic_workflow
        elsif repository.page.nojekyll?
          :static_content
        else
          :legacy_jekyll
        end
      end
    end
  end
end
