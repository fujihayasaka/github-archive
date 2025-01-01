# typed: false
# frozen_string_literal: true

# This is the Web specific implementation of
# the methods needed to evaluate all the policies.
module ConditionalAccess::Web::Helpers

  # application controller specific implementation to support the included policies
  def anonymous?
    !callback.send(:logged_in?)
  end

  def anonymous_for_authzd?
    callback.respond_to?(:logged_in?, true) ? !callback.send(:logged_in?) : false
  end

  # application controller specific implementation to support the included policies
  def actor
    callback.send(:current_user)
  end

  def web_session
    callback.send(:user_session)
  end

  def web_session_for_authzd
    callback.respond_to?(:user_session, true) ? callback.send(:user_session) : nil
  end

  def actor_ip
    callback.send(:remote_ip)
  end

  def actor_ip_for_authzd
    (callback.respond_to?(:remote_ip, true) && callback.send(:remote_ip)) || GitHub.context[:actor_ip]
  end

  def safe_request_method?
    callback.respond_to?(:request) && callback.send(:request).get?
  end

  def repository
    callback.send(:current_repository)
  end

  def repository_for_authzd
    callback.respond_to?(:current_repository, true) ? callback.send(:current_repository) : nil
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_key_for_authzd
    callback.respond_to?(:authenticated_key, true) ? callback.send(:authenticated_key) : nil
  end

  def authenticated_through_integration?
    false
  end

  def request_access_security_header
    callback.request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER]
  end

  def request_access_security_header_for_authzd
    callback.respond_to?(:request) && callback.request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER]
  end

  def authzd_cap_actor
    callback.respond_to?(:current_user, true) ? callback.send(:current_user) : nil
  end

  def authzd_cap_request_attributes
    attrs = {}

    if actor_ip_for_authzd
      attrs["conditional.access.ip"] = actor_ip_for_authzd
    end

    if repository_for_authzd
      attrs["conditional.access.repository_id"] = repository_for_authzd.id
    end

    if anonymous_for_authzd?
      attrs["conditional.access.anonymous"] = true
    end

    if authenticated_key_for_authzd
      attrs["conditional.access.authenticated_key_id"] = authenticated_key_for_authzd.id
    end

    if authenticated_through_integration?
      attrs["conditional.access.authenticated_through_integration"] = true
    end

    if safe_request_method?
      attrs["conditional.access.safe_request_method"] = true
    end

    if web_session_for_authzd
      attrs["conditional.access.web_session_id"] = web_session_for_authzd.id
    end

    if request_access_security_header_for_authzd
      attrs["conditional.access.request_access_security_header"] = request_access_security_header_for_authzd
    end

    attrs
  end
end
