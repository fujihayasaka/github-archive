# typed: true
# frozen_string_literal: true

# Contains JSON and JSONP endpoints which are completely stateless and do not
# require sessions or cookies. Ultimately we would like to move these out
# of the main app and into the API or another location using a separate domain
# to limit same-origin related attach vectors.
#
# See https://github.com/github/github/issues/42432 for more details.
class Gists::StatelessController < Gists::GistsController
  skip_before_action :auto_oauth

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:show]

  def show
    files = embed_files(params[:file])
    data = {
      description: this_gist.description,
      public: this_gist.public?,
      created_at: this_gist.created_at,
      files: files.map(&:name),
      owner: this_gist.user_param,
      div: render_to_string(partial: "gists/gists/embed_content",
        formats: :html,
        locals: {
          view: create_view_model(Gists::ShowPageView,
            gist: this_gist,
            revision: commit_sha,
            files: files,
          )
        }
      ),
      stylesheet: view_context.gist_embed_stylesheet_url,
    }

    if jsonp_callback_valid?(params[:callback])
      render  json: data,
              content_type: "application/javascript",
              callback: params[:callback]
    else
      render json: data
    end
  end

  private

  # Disable user sessions in this controller.
  def stateless_request?
    true
  end

  VALID_JSONP = /\A[a-z0-9\.\[\]_]+\z/i

  # Internal: Is the given callback name valid?
  def jsonp_callback_valid?(callback)
    callback && callback =~ VALID_JSONP
  end

  # Internal: Prefix the JSONP response with a comment
  #           See: https://github.com/github/github/pull/20547
  def prefix_jsonp_callback(callback)
    "/**/#{callback}"
  end

end
