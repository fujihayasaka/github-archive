# typed: true
# frozen_string_literal: true

class Copilot::Workbench::FilesController < Copilot::Workbench::AbstractWorkbenchController
  def show
    # Use spark-template repo instead of workbench-template if feature flag is enabled
    template_repo_name = "github/spark-template"

    repo = Repositories.domain.by_qualified_name(template_repo_name)
    if repo.nil? && ENV["CODESPACE_NAME"]
      # If in dev, fall back to a known github.localhost repo
      # Won't work for running dev server etc. in workbench, but allows frontend to limp along
      repo = Repositories.domain.by_qualified_name("monalisa/smile")
    end

    # NOTE: Must downcast because IRepository doesn't have blob method
    repo = T.cast(repo, Repository) # rubocop:disable GitHub/AvoidCast
    blob = repo.blob(repo.default_oid, path_string) if path_string.present?

    render json: {
      blobContents: blob&.data,
      path: path_string,
    }
  end
end
