# typed: true
# frozen_string_literal: true

module RepositoryImports
  class AuthorsController < RepositoryImports::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Memex,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      only: [:author_suggestions]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    # Public: List the authors that were found during the import.
    def index
      if repository_import.authors_found?
        view = create_view_model(RepositoryImports::ShowView, repository_import: repository_import)
        render "repository_imports/authors/index", locals: { view: view }
      else
        redirect_to repository_import_path(repository_import.url_params)
      end
    end

    # Public: List suggested github users to map an author to.
    def author_suggestions # rubocop:todo GitHub/UseRestfulActions
      headers["Cache-Control"] = "no-cache, no-store"

      respond_to do |format|
        format.html_fragment do
          render partial: "repository_imports/authors/author_suggestions",
            formats: :html,
            locals: {
              view: create_view_model(RepositoryImports::Authors::AuthorSuggestionsView, query: params[:q])
            }
        end
      end
    end

    # Public: Update an author with email or name, email, and github login.
    def update
      user = nil
      author_params = {
        author_id: params[:id].to_i,
      }

      if params[:author].present?
        if user = User.find_by_login(params[:author])
          author_params[:email] = user.public_attribution_email
          author_params[:name] = user.profile.try(:name)
          author_params[:login] = user.login # rubocop:disable GitHub/DoNotAllowLogin login is used in an update below, see RepositorySourceImport#update_author
        else
          author_params[:email] = params[:author]
        end
      else
        author_params[:email] = nil
        author_params[:name] = nil
        author_params[:login] = nil
      end

      author = repository_import.update_author(**author_params)

      respond_to do |format|
        format.html do
          render partial: "repository_imports/authors/author", locals: {
            view: create_view_model(RepositoryImports::Authors::AuthorView,
              author: author,
              user: user,
              repository_import: repository_import
            )
          }
        end
      end
    end
  end
end
