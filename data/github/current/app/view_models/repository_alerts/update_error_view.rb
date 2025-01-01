# typed: true
# frozen_string_literal: true

module RepositoryAlerts
  class UpdateErrorView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :repository, :manifest_path, :package_name, :state, :dependency_update

    def update_error_title
      dependency_update.error_title
    end

    def update_error_body
      dependency_update.error_body
    end

    def page_title
      "#{update_error_title} · #{repository.name_with_display_owner}"
    end

    def available_alerts
      @available_alerts ||= repository.repository_vulnerability_alerts
        .for_manifest_and_package(manifest_path: manifest_path, package_name: package_name)
    end

    def alerts
      @alerts ||= open? ? available_alerts.open : available_alerts.dismissed
    end

    def missing?
      !alerts.exists? || !dependency_update&.error?
    end

    def open?
      state == "open"
    end

    def short_manifest_path
      helpers.short_manifest_file_path(manifest_path)
    end

    def manifest_blob_path
      urls.blob_view_path(manifest_path, repository.default_branch, repository)
    end
  end
end
