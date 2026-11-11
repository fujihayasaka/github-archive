# typed: true
# frozen_string_literal: true

class Gists::PreviewsController < Gists::ApplicationController
  include OrganizationsHelper
  include TextHelper

  def create
    if !logged_in? && !GitHub.anonymous_gist_creation_enabled?
      return head :forbidden
    end

    info = {
      "data" => params[:code],
      "path" => params[:blobname],
    }
    # Instantiate an in-memory blob as Gists can be previewed before they are created
    blob = TreeEntry.new(Gist.new, info)
    context = {
      blob: blob,
    }
    html = GitHub::Goomba::MarkupPipeline.to_html(nil, context, nil)

    render html: html
  end
end
