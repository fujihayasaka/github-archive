# typed: false
# frozen_string_literal: true

# Detect and handle when a user is trying to update out of date content
# for any model that has a `body_version`.
#
# See also UserContent, which mixes in body_version to
# many of our standard comment models.
module StaleModelDetection
  # Public: Render error response when user is acting on stale data.
  def render_stale_error(model: nil, error:, path:)
    task_list_update = !params[:task_list_track].nil?

    event = task_list_update ? "task_list_update" : "comment_edit"
    GitHub.dogstats.increment "stale", tags: ["error:render_error", "event:#{event}"]

    respond_to do |format|
      format.json do
        json = { stale: true }
        if model
          json[:updated_markdown] = model.body if model.body
          json[:updated_html] = model.body_html if model.body_html
          json[:version] = model.body_version if model.body_version
        end

        render status: :unprocessable_entity, json: json
      end

      format.html do
        flash[:error] = error

        redirect_to path
      end
    end
  end

  # Public: Determine if the request for this model is based on stale data.
  # Requires the `X-Body-Version` request header or :body_version param to be set.
  def stale_model?(model)
    version = request.headers["X-Body-Version"] || request.params[:body_version]
    return false unless version

    model.body_version != version
  end

end
