# typed: false
# frozen_string_literal: true

module Api::App::HelpersDependency
  # Public: Helper to coerce String params into Booleans
  #
  # value - The param value
  #
  # Returns a Boolean
  def parse_bool(value)
    ActiveRecord::Type::Boolean.new.deserialize(value)
  end

  # Applies the `since` scoping to a query.
  def since_filter(scope)
    time = Time.parse(time_param!(:since).to_s).getlocal
    scope.where(["#{scope.table_name}.updated_at >= ?", time])
  rescue ArgumentError
    docs_url = case scope.table_name
    when "pull_requests"
      "/v3/pulls/#list-pull-requests"
    else
      "/v3/issues/#list-issues"
    end
    deliver_error! 422,
      message: "Invalid datetime for since",
      documentation_url: docs_url
  end

  # Ensures the request supplies the required media types for a resource.
  # Usually used for preview periods.
  #
  # Halts if the proper media type is not supplied.
  def ensure_acceptable_media_types!
    if unacceptable_media_types?
      message = "Unsupported 'Accept' header: '#{request.accept.map(&:entry).join(", ")}'. " +
        "Must accept 'application/json'."
      deliver_error! 415, message: message,
        documentation_url: "/v3/media"
    end
  end

  # Given a user authenticating through an App -- can that App
  # modify the App given? In other words, this method checks
  # to ensure that App X is modifying values for App X,
  # and no other App
  #
  # **NOTE:** This method should be called AFTER
  # any relevant Egress role is checked!
  #
  def allowed_to_modify_app?(app_id:)
    # server-server: is it modifying itself?
    if current_user.respond_to?(:installation)
      current_integration.id == app_id.to_i
    # user-server: is it modifying itself?
    elsif current_user.using_auth_via_integration?
      current_user.oauth_access.application_id == app_id.to_i
    # user or OAuth app, go for it
    else
      true
    end
  end
end
