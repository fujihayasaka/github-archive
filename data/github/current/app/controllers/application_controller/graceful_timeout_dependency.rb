# typed: false
# frozen_string_literal: true

module ApplicationController::GracefulTimeoutDependency
  extend ActiveSupport::Concern

  included do
    helper_method :timeout_error?
  end

  class_methods do
    # Rescue timeout exceptions so that a more-graceful error page can be
    # displayed instead of the default timeout error page. The macro takes a block
    # that's evaluated in the controller instance when a timeout occurs. The block
    # is passed the timeout exception object that triggered the block. Handlers
    # may render or whatever to manage displaying a meaningful timeout page.
    #
    #   class MyController
    #     def show
    #       # some potentially long running action
    #     end
    #
    #     rescue_from_timeout do |boom|
    #       render :template => 'some/timeout'
    #     end
    #   end
    #
    # It's also possible to limit the scope of the handler to only certain actions
    # or excepting certain actions. The argument format is the same as the
    # builtin before_action, after_action, and around_action macros.
    #
    #     rescue_from_timeout :only => [:show] do |boom|
    #       render :template => 'some/timeout'
    #     end
    #
    # The timeout_error? method defined in this file determines which exceptions
    # are considered timeouts.
    #
    # Caching
    # -------
    #
    # When a real timeout occurs, this is flagged in memcached for the current
    # URL. Subsequent requests for the same URL will generate a timeout immediately
    # instead of allowing the long running action to run repeatedly.
    #
    # This timeout flag is cached for 30 minutes, after which it expires and the action
    # will be requested as normal. This provides protection from denial of service
    # while still ensuring that working repos are shown once error-creating
    # conditions (like a database failure) have passed.
    #
    # You can manage the timeout cache via the special "_timeout" query param.
    # These commands are supported:
    #
    # ?_timeout=1      - Simulate a timeout on this page.
    # ?_timeout=clear  - Clear the cached timeout state and attempt to process the
    #                    action for real again.
    # ?_timeout=set    - Mark the timeout cache for this URL so that the page
    #                    appears as a timeout until its next cleared.
    #
    # Exceptions are reported to failbot only the first time a page timeout
    # occurs. Exceptions are not reported on simulated timeout due to either a
    # _timeout=1 command or to the page's timeout cache being set.
    def rescue_from_timeout(options = {}, &block)
      around_action options do |controller, action|
        controller.rescue_from_timeout_filter(action, remember: true, &block)
      end
    end

    # Same as the above except with an indication that we should never store
    # the timeout in cache.  This is intended for areas whose timeout profile
    # is intermittent e.g. due to caching effects, such that a second attempt
    # might cause the page to succeed, so we should not remember and replay the
    # timeout.
    def rescue_from_timeout_without_replay(options = {}, &block)
      around_action options do |controller, action|
        controller.rescue_from_timeout_filter(action, remember: false, &block)
      end
    end
  end

  # Internal: The request level around filter. This is registered for each
  # rescue_from_timeout macro invocation. This shouldn't be called directly.
  # Use the rescue_from_timeout macro to set this up.
  #
  # action   - The callable action handler. Continues the filter chain,
  #            eventually invoking the action when called.
  # remember - Should we remember the timeout and store it in cache so all
  #            other requests to the same path get a timeout without even trying?
  # block    - The handler block run when an exception occurs. Both legit timeouts
  #            and simulated timeouts cause the handler to be called.
  #
  # Returns the result of the action.
  def rescue_from_timeout_filter(action, remember:, &block)
    simulated = false
    command = params[:_timeout]
    timeout_key = rescue_from_timeout_key

    # must be staff for _timeout commands. clear and 1 commands are supported
    # for atom and raw requests where the session is disabled.
    if command && (site_admin? || (stateless_request? && command != "set"))
      if command == "clear"
        GitHub.dogstats.increment("rescued_timeout", tags: ["action:staff_clear"])
        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub.kv.del(timeout_key) # rubocop:todo GitHub/DoNotUseGlobalKv
        end
      elsif command == "set"
        GitHub.dogstats.increment("rescued_timeout", tags: ["action:staff_set"])
        simulated = true
        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub.kv.set(timeout_key, "1", expires: 30.minutes.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
        end
      else
        simulated = true
      end
    else
      simulated = GitHub.kv.exists(timeout_key).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    raise Timeout::Error, "simulated" if simulated

    action.call

  rescue Exception => boom # rubocop:todo Lint/GenericRescue
    raise if !timeout_error?(boom)

    if remember && !simulated
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.kv.set(timeout_key, "1", expires: 30.minutes.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end

    controller_action_name = "#{controller_name.parameterize}.#{action_name.parameterize}"
    GitHub.dogstats.increment "rescued_timeout", tags: ["action:#{controller_action_name}"]

    instance_exec(boom, &block)
  end

  # Version for this action cache, used for busting the cache when needed
  ACTION_TIMEOUT_VERSION = "v2"

  # Internal: Cache key used to record that the current request timed out. This
  # is then checked on subsequent requests so the timeout can be fired
  # immediately instead of performing the long operation each time.
  #
  # Cache keys are generated from the path and query string parts of the URL
  # currently. This has some downsides in that you can simply add to the query
  # string or url encode some characters to defeat the cache. The query params are
  # sorted at least so we should get canonical keys even if query param order
  # changes.
  #
  # Returns a string cache key that identifies the current request URL.
  def rescue_from_timeout_key
    path, query = request.fullpath.split("?", 2)
    query &&= query.split("&").reject { |p| p =~ TIMEOUT_IGNORE_PARAMS }.sort
    query = nil if query.blank?
    "action-timeout:#{ACTION_TIMEOUT_VERSION}:#{Digest::SHA256.hexdigest(path)}:#{query && Digest::SHA256.hexdigest(query.to_s)}"
  end
  TIMEOUT_IGNORE_PARAMS = /\A(?:skipmc|_timeout|slide)=/

  # Determine if an exception is a timeout error, taking into account
  # ActionView::TemplateError exceptions raised from within templates.
  def timeout_error?(exception)
    case exception
    when ::Timeout::Error
      GitHub.dogstats.increment("rescued_timeout", tags: ["error:timeout_error"])
      true
    when ApplicationHelper::GitTemplateTimeout
      GitHub.dogstats.increment("rescued_timeout", tags: ["error:application_helper_git_template_timeout"])
      true
    when GitRPC::Failure
      # When a GitRPC operation receives a GitTemplateTimeout exception, it will sometimes `rescue` that exception
      # and wrap it in a `GitRPC::Failure` before re-raising it. We need to make sure we treat that wrapped exception
      # as a timeout
      GitHub.dogstats.increment("rescued_timeout", tags: ["error:gitrpc_timeout"])
      timeout_error?(exception.original)
    when GitRPC::Timeout
      GitHub.dogstats.increment("rescued_timeout", tags: ["error:gitrpc_timeout"])
      true
    when ActionView::TemplateError
      GitHub.dogstats.increment("rescued_timeout", tags: ["error:action_view_template_error"])
      timeout_error?(exception.cause)
    when ActiveRecord::StatementInvalid
      GitHub.dogstats.increment("rescued_timeout", tags: ["error:active_record_statement_invalid"])
      timeout_error?(exception.cause)
    else
      false
    end
  end
end
