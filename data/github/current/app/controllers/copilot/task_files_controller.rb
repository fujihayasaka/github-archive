# typed: true
# frozen_string_literal: true

class Copilot::TaskFilesController < Copilot::TaskControllerBase

  def show
    blob = current_repository.blob(pull.head_sha, path_string, blob_limits)
    render json: {
      blobContents: blob&.data,
      path: path_string,
    }
  end
end
