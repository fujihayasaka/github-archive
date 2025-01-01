# typed: true
# frozen_string_literal: true

class WorkspaceEditor::OverviewController < WorkspaceEditor::ControllerBase

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
  only: [:show]

  def show
    body_html = async_pull_body_html.sync
    respond_to do |format|
      format.json do
        render json: {
          bodyHtml: body_html,
          titleHtml: GitHub::Goomba::TitleMarkdownFilter.call(pull.title),
          labels: labels,
        }
      end
    end
  end

  private

  def labels
    pull.labels.map { |label| { name: label.name, color: label.color } }
  end

  def pull
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end

  def async_pull_body_html
    context = {
      viewer: current_user
    }

    pull.async_body_html(context: context).then do |body_html|
      body_html || GitHub::HTMLSafeString::EMPTY
    end
  end
end
