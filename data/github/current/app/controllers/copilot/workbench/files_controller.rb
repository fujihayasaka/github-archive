# typed: true
# frozen_string_literal: true

class Copilot::Workbench::FilesController < WorkspaceEditor::ControllerBase
  def show
    workbench = T.must(::Workbench.load_workbench(current_user.id, params[:id]))
    blob = workbench.dig("files", path_string)

    render json: {
      blobContents: blob,
      path: path_string,
    }
  end
end
