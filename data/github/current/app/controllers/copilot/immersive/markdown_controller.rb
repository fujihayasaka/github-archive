# typed: true
# frozen_string_literal: true

class Copilot::Immersive::MarkdownController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include BlobMarkupHelper
  include TextHelper

  before_action :login_required
  before_action :try_parse_json_params

  allow_verified_fetch only: [:index]

  def index
    info = {
      "data" => params[:content],
      "path" => params[:filename],
    }
    # MarkupPipeline expects a blob object that belongs to a repository. We take inspiration from Gists::PreviewsController
    # and create a blob entry this way.
    blob = TreeEntry.new(Gist.new, info)
    html, _ = format_blob_with_result(blob, { add_tabindex_to_headings: true })

    render json: {
      html: html,
    }
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
