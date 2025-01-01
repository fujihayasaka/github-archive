class ApplicationController < ActionController::API
  # Rescue everything so we can track it via Failbot
  rescue_from Exception, with: :handle_generic_exception

  before_action :initialize_log_data
  around_action :with_log_context

  # Internal: A Hash of data to be logged that is stored in the request env.
  # This will eventually be logged by Rack::RequestLogger.
  #
  # Returns a Hash.
  def log_data
    request.env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= HashWithIndifferentAccess.new
  end

  # Internal: Store application specific data for this request to be logged.
  #
  # Returns nothing.
  def initialize_log_data
    log_data.merge!(failbot_context)
  end

  def failbot_context
    {
      "app" => "dependency-graph-api".freeze,
      "code.function" => "%s#%s" % [self.class.name, params[:action]],
      "code.namespace" => self.class.name,
      "db.connection_string" => db_connection_url(ActiveRecord::Base.connection_pool),
      "gh.repo.public" => request.headers["X-GitHub-Is-Public"],
      "gh.request_id" => request.headers["X-GitHub-Request-Id"],
      "gh.session_id" => request.headers["X-GitHub-Session-Id"],
      "gh.user.name" => request.headers["X-GitHub-User"],
      "http.request.method" => request.env["REQUEST_METHOD"].downcase,
      "user_agent.original" => request.user_agent.to_s
    }.delete_if { |key, value| value.blank? }
  end

  protected

  def db_connection_url(connection_pool)
    config = connection_pool.db_config.configuration_hash
    "#{config[:username]}@#{config[:host]}#{config[:socket]}/#{config[:database]}"
  end

  def handle_generic_exception(e)
    Failbot.report(e, failbot_context)

    if Rails.env.test? || Rails.env.development?
      raise e
    else
      render status: 500, plain: "500-Internal Server Error"
    end
  end

  private

  def with_log_context
    DependencyGraph.logger.with_named_tags(log_data) do
      yield
    end
  end
end
