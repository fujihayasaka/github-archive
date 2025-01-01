# typed: true
# frozen_string_literal: true

module RepositoryImports
  class AuthController < RepositoryImports::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests
    # Public: Provide the importer with the auth credentials needed to continue
    # the detection and import from a source repository.
    def update
      if params[:vcs_username].present? && params[:vcs_password].present?
        repository_import.provide_auth(
          vcs_username: params[:vcs_username],
          vcs_password: params[:vcs_password],
        )
      else
        flash[:notice] = "Please provide a username and password."
      end

      redirect_to repository_import_path(repository_import.url_params)
    end
  end
end
