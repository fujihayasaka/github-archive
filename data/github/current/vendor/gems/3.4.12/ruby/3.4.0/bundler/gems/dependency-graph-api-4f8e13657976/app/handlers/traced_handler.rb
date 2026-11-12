class TracedHandler
  ENV_ARG_INDEX = 1.freeze

  class ValidationError < StandardError
    attr_reader :twirp_error
    def initialize(twirp_error, msg = nil)
      @twirp_error = twirp_error
      super(msg)
    end
  end

  def trace(**payload, &block)
    return if OpenTelemetry::Trace.current_span.nil?

    payload.map do |k, v|
      OpenTelemetry::Trace.current_span.set_attribute(k.to_s, v)
    end

    DependencyGraph.logger.log_and_failbot_context(payload) do
      begin
        block.call
      rescue Rack::Timeout::RequestTimeoutException, StandardError => ex
        DependencyGraph.logger.error("An unexpected service error has occurred. Reporting to Failbot.", payload, ex)
        Failbot.report(ex)
        return Twirp::Error.internal("An unexpected service error has occurred.")
      end
    end if block_given?
  end

  def is_property_present(obj:, symbol:)
    obj[symbol.to_s].present? && !0.equal?(obj[symbol.to_s]) # the equal? method is more tolerant of heterogenous types
  end

  def twirp_400(args = {})
    reason = args[:reason] || "mandatory fields"
    Twirp::Error.invalid_argument(reason, argument: args[:fields].join(","))
  end

  def twirp_404(args = {})
    reason = args[:reason] || "not found"
    Twirp::Error.not_found(reason)
  end

  def find_by_github_repo_id(repository_id, metadata_field_name, tracing_log)
    GitHub::Telemetry.tracer.in_span("find_by_github_repo_id") do
      repository = Repository.find_by(github_repository_id: repository_id)
      tracing_log[(metadata_field_name + "_existing_repo_looked_up").to_sym] = true unless repository.nil?
      return repository unless repository.nil?
    end
  end

  def self.add_log_context(name)
    original_method = instance_method(name)
    define_method(name) do |*args|
      if args.size == 2 # second parameter is populated by env data
        DependencyGraph.logger.log_and_failbot_context(get_log_context(args[ENV_ARG_INDEX])) do
          original_method.bind(self).call(*args)
        end
      else
        # call plain method
        original_method.bind(self).call(*args)
      end

    end
  end

  private

  def get_log_context(env)
    context_base = env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= HashWithIndifferentAccess.new
    context_base.merge!(
      {
        "app" => "dependency-graph-api".freeze,
        "user_agent.original" => env[:HTTP_User_Agent],
        "controller" => env[:RPC_Handler],
        "gh.request_id" => env[:HTTP_X_GitHub_Request_Id],
        "gh.user.name" => env[:HTTP_X_GitHub_User],
        "gh.session_id" => env[:HTTP_X_GitHub_Session_Id],
        "gh.repo.public" => env[:HTTP_X_GitHub_Is_Public]
      }.delete_if { |key, value| value.blank? }
    )
    context_base
  end
end
