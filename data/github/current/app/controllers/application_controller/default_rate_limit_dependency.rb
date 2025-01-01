# typed: strict
# frozen_string_literal: true

module ApplicationController::DefaultRateLimitDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  NON_MUTATIVE_REQUEST_METHODS = T.let(%w[GET HEAD OPTIONS TRACE].freeze, T::Array[String])

  private

  sig { returns(T::Boolean) }
  def endpoint_rate_limited_by_default?
    mutative_request_method?
  end

  sig { returns(T::Boolean) }
  def mutative_request_method?
    NON_MUTATIVE_REQUEST_METHODS.exclude?(request.method)
  end

  sig { returns(String) }
  def default_rate_limit_key
    return "#{self.class.to_s.underscore}.#{action_name}:#{current_user.id}" if logged_in?

    rate_limit_key_by_ip
  end

  sig { returns(String) }
  def rate_limit_key_by_ip
    "#{self.class.to_s.underscore}.#{action_name}:#{request.remote_ip}"
  end
end
