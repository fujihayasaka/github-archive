# typed: true
# frozen_string_literal: true

class WorkspaceEditor::FilesController < WorkspaceEditor::ControllerBase

  def show
    commit_oid = params[:commit_oid]
    blob = current_repository.blob(commit_oid, path_string, blob_limits)
    language_details = blob ? Linguist.detect(blob) : nil

    render json: {
      blobContents: blob&.data,
      commitOid: commit_oid,
      languageId: language_details&.language_id,
      languageName: language_details&.name,
      path: path_string,
      refName: pull.head_ref,
    }
  end
end
