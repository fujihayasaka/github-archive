# typed: true
# frozen_string_literal: true

module RepositoryImports
  class LargeFilesController < RepositoryImports::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Billing,
      ApplicationRecord::Iam,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Memex,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    # Public: List large files found during import and provide a form for opting
    # in or out of large file storage.
    def index
      unless repository_import.has_large_files?
        return redirect_to repository_import_path(repository_import.url_params)
      end

      page = if params[:page].nil?
        1
      else
        params[:page].to_i
      end

      view = create_view_model(RepositoryImports::LargeFiles::IndexView,
        repository_import: repository_import,
        page: page,
      )

      respond_to do |format|
        format.html do
          if pjax?
            render partial: "repository_imports/large_files/lfs_file_list", locals: { view: view }
          else
            render "repository_imports/large_files/index", locals: { view: view }
          end
        end
      end
    end

    # Public: Opt-in or out of using large file storage.
    def update
      data = {
        "committer" => {
          "name"        => current_user.git_author_name,
          "email"       => current_user.git_author_email,
          "time"        => Time.now.to_i,
          "time_offset" => current_user.time_zone.utc_offset,
        },
      }

      if params[:gitlfs] == "opt-in"
        repository_import.lfs_opt_in(data)
      else
        repository_import.lfs_opt_out(data)
      end

      redirect_to repository_import_path(repository_import.url_params)
    end
  end
end
