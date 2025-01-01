# typed: true
# frozen_string_literal: true

module GitHub::Middleware::AnonymousRequest
  # Is this request anonymous?
  #
  # This uses a simple heuristic: is a user session cookie present?
  #
  # Returns true or false.
  def anonymous_request?(request)
    cookies = request.cookies
    session = cookies["user_session"] || cookies["gist_user_session"]
    session.nil? || session.empty?
  end
end
