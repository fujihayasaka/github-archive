# typed: true
# frozen_string_literal: true

module RepositoryImports
  class ProjectController < RepositoryImports::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests
    # Public: Update an import with a project choice.
    def update
      if params[:project] && chosen = repository_import.projects.find { |project| project.to_param == params[:project] }
        repository_import.choose_project(chosen)
      else
        flash[:notice] = "Please provide a valid project."
      end

      redirect_to repository_import_path(repository_import.url_params)
    end
  end
end
