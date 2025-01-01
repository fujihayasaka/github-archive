# typed: true
# frozen_string_literal: true

class RelatedRepositoriesController < ApplicationController
  include RepositoryControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:index]

  def index
    org_query_phrase = "org:#{current_repository.owner.login}" if current_repository&.in_organization? # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
    query_phrase_prefix = "user:#{current_user.login} #{org_query_phrase}".strip # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
    query_text = permitted_params[:q]
    experimental_select_panel = permitted_params[:experimental] == "1"

    query = Search::Queries::RepoQuery.new(
      current_user: current_user,
      user_session: user_session,
      remote_ip: request.remote_ip,
      phrase: "#{query_phrase_prefix} #{query_text}",
    )

    repos = query.execute.results.map { |result| result["_model"] }.select { |r| r.has_issues? && !r.archived? }

    respond_to do |format|
      format.html_fragment do
        render partial: "repositories/repository_results", formats: :html, locals: {
          repositories: repos,
          experimental_select_panel: experimental_select_panel,
          menu_id: params[:menu_id],
        }
      end
      format.html do
        render partial: "repositories/repository_results", locals: {
          repositories: repos,
          experimental_select_panel: experimental_select_panel,
          menu_id: params[:menu_id],
        }
      end
    end
  end

  private

  def permitted_params
    params.permit(:q, :user_id, :repository, :experimental, :menu_id)
  end
end
