# frozen_string_literal: true

# Detect and handle when a user is trying to update out of date content
# for any model that has a `body_version`.
module StaleModelDetection
  # Public: Determine if the request for this model is based on stale data.
  # Requires the `X-Body-Version` request header or :body_version param to be set.
  def stale_model?(model)
    version = request.headers["X-Body-Version"] || request.params[:body_version]
    return false unless version

    model.body_version != version
  end
end
