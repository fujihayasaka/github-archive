# typed: true
# frozen_string_literal: true

module ApplicationController::AuditDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :setup_audit_context
  end

  private

  def setup_audit_context
    Audit.context.push(initial_audit_context)
  end

  def initial_audit_context
    request_url =
      begin
        Rack::RequestLogger.url_for_logging("#{request.protocol}#{request.host_with_port}#{request.fullpath}")
      rescue NoMethodError
      end

    {
      actor_ip: request.remote_ip,
      user_agent: strip_user_agent(request.user_agent.to_s),
      from: "%s#%s" % [params[:controller], params[:action]],
      method: request.try(:request_method),
      request_id: request_id,
      server_id: Rack::ServerId.get(request.env),
      request_category: request_category,
      controller_action: params[:action],
      url: request_url,
      client_id: persistent_client_id,
      referrer: request.referrer,
      device_cookie: cookies[:_device_id],
      is_robot: robot?
    }
  end

  def strip_user_agent(user_agent)
    user_agent.lstrip.delete_prefix("=")
  end
end
