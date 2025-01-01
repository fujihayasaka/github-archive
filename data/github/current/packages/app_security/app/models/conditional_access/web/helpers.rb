# typed: false
# frozen_string_literal: true

# This is the Web specific implementation of
# the methods needed to evaluate all the policies.
module ConditionalAccess::Web::Helpers

  # application controller specific implementation to support the included policies
  def anonymous?
    !callback.send(:logged_in?)
  end

  # application controller specific implementation to support the included policies
  def actor
    callback.send(:current_user)
  end

  def web_session
    callback.send(:user_session)
  end

  def actor_ip
    callback.send(:remote_ip)
  end

  def safe_request_method?
    callback.send(:request).get?
  end

  def repository
    callback.send(:current_repository)
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_through_integration?
    false
  end

  def request_access_security_header
    callback.request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER]
  end
end
