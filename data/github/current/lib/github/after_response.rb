# typed: true
# frozen_string_literal: true

module GitHub
  class AfterResponse
    TIMEOUT_IN_SECONDS = 6

    class DuplicatePerformError < StandardError
    end

    class TimeoutError < StandardError
    end

    attr_reader :tags, :to_perform

    def initialize(env)
      @tags = []

      env["rack.after_reply"] ||= []
      env["rack.after_reply"] << -> do
        return if self.to_perform.empty?
        self.generate_tags(env)
        self.call
      end

      @to_perform = {}
    end

    def enabled?
      true
    end

    def call
      request_thread = Thread.current
      timer_thread = Thread.new do # rubocop:disable GitHub/ThreadUse
        sleep(TIMEOUT_IN_SECONDS)
        GitHub.dogstats.increment("after_response.timeout", tags: tags)
        error = TimeoutError.new("timed out in after_response")
        Failbot.report_from_thread(request_thread, error)
        exit!
      end

      Rails.application.executor.wrap { call_performs }
    ensure
      timer_thread&.kill
    end

    def perform(name, &block)
      if @to_perform[name]
        raise DuplicatePerformError.new("#{name} is already defined in AfterResponse")
      else
        @to_perform[name] = block
      end
    end

    private

    def call_performs
      started_at = GitHub::Dogstats.monotonic_time

      @to_perform.each do |_name, block|
        begin
          block.call(self)
        rescue Object => e # rubocop:todo Lint/GenericRescue
          Rails.logger.error(e) if Rails.env.development? # Prevent this from being hidden in development
          Failbot.report(e)
          raise if GitHub.after_response_raise_on_exception? # re-raise the original exception
        end
      end

      elapsed = GitHub::Dogstats.duration(started_at)

      GitHub.dogstats.distribution("after_response.total.dist.time", elapsed, tags: tags)
    end

    def generate_tags(env)
      @tags = []

      path_params = env["action_dispatch.request.path_parameters"]
      if path_params
        @tags << "controller:#{path_params[:controller]}"
        @tags << "action:#{path_params[:action]}"
      end

      if env.key?(GitHub::TaggingHelper::PROCESS_REQUEST_LOGGED_IN)
        @tags << "logged_in:#{env[GitHub::TaggingHelper::PROCESS_REQUEST_LOGGED_IN]}"
      end

      category = env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY] || GitHub::TaggingHelper::CATEGORY_DEFAULT
      @tags << "category:#{category}"
    end
  end
end
