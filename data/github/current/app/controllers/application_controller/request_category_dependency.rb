# typed: true
# frozen_string_literal: true

# Classifies requests into one of a small number of categories: browser, api,
# robot, feed, raw, or other. Useful for performance monitoring and
# exception notifications.
#
# The category set here is used in stats reported to amen / graphite. The
# category breakdowns are available at github.unicorn.<category> and include
# response time, gc, mysql, etc. timeseries data.
module ApplicationController::RequestCategoryDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationController))
    after_action :request_category_log_filter
  end

  # When determining whether or not we should `touch` a user session to
  # potentially bump the accessed_at value (extending the life of the session),
  # we limit the definition of "activity" to full/pjax-based navigation. These
  # categories include link/form/URL bar requests that are not triggered by XHR.
  # We exclude XHR because pages periodically receive updates e.g. issue
  # comments which could extend the session when no human was around.
  FULL_NAVIGATION_REQUEST_CATEGORIES = %w(browser_full browser_pjax)

  # Sets the request category for the purpose of tracking what type of request
  # is currently being processed when reporting stats or exceptions.
  #
  # category - The string category name for the request. Possible values include:
  #            browser, api, robot, raw, feed, and other.
  #
  # Returns the request category if set.
  def set_request_category(category, set_datadog_category: true)
    return if category.nil?
    return unless env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY].nil?
    set_request_category!(category, set_datadog_category: set_datadog_category)
  end

  def set_request_category!(category, set_datadog_category: true)
    Failbot.push(request_category: category && category.to_s)
    env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY] = category && category.to_s
    if set_datadog_category
      env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY_DATADOG] = category && category.to_s
    end
    # If the request category is updated, we need to reset the query logs comment cache so it's updated.
    ActiveRecord::QueryLogs.cached_comment = nil
  end

  # The current request's category. This should be set using one of the
  # set_request_category methods.
  def request_category
    env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY] || GitHub::TaggingHelper::CATEGORY_DEFAULT
  end

  def set_request_category_datadog(category)
    return if category.nil?
    return unless env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY_DATADOG].nil?
    env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY_DATADOG] = category && category.to_s
  end

  def set_request_pjax(pjax)
    return if pjax.nil?
    return unless env[GitHub::TaggingHelper::PROCESS_REQUEST_PJAX].nil?
    set_request_pjax!(pjax)
  end

  def set_request_pjax!(pjax)
    env[GitHub::TaggingHelper::PROCESS_REQUEST_PJAX] = pjax && pjax.to_s
  end

  def set_request_turbo(turbo)
    return if turbo.nil?
    return unless env[GitHub::TaggingHelper::PROCESS_REQUEST_TURBO].nil?
    set_request_turbo!(turbo)
  end

  def set_request_turbo!(turbo)
    env[GitHub::TaggingHelper::PROCESS_REQUEST_TURBO] = turbo && turbo.to_s
  end

  def set_request_logged_in(logged_in)
    return if logged_in.nil?
    return unless env[GitHub::TaggingHelper::PROCESS_REQUEST_LOGGED_IN].nil?
    set_request_logged_in!(logged_in)
  end

  def set_request_logged_in!(logged_in)
    env[GitHub::TaggingHelper::PROCESS_REQUEST_LOGGED_IN] = logged_in && logged_in.to_s
  end

  def set_staff_tag
    return if !env[GitHub::TaggingHelper::PROCESS_REQUEST_STAFF_USER].nil?
    env[GitHub::TaggingHelper::PROCESS_REQUEST_STAFF_USER] = current_user&.employee? ? "true" : "false"
  end

  # Filter used to classify the request under a category based on the
  # user agent, hostname, path or other aspects of the request. If no request
  # category is set by this method, "other" is assumed.
  FULL_NAVIGATION_REQUEST_AGENTS = /\A(?:Mozilla|Opera|Lynx)/
  def request_categorization_filter
    user_agent = request.user_agent.to_s
    set_request_logged_in logged_in?.to_s
    set_staff_tag

    case
    when robot = robot?
      set_request_category "robot"
    when request.format && request.format.atom?
      set_request_category "atom"
    when request.xhr? && !pjax? && !turbo_type && react_navigation_type.nil?
      set_request_category "ajax"
    when user_agent =~ FULL_NAVIGATION_REQUEST_AGENTS
      if pjax?
        suffix = "_pjax"
        set_request_pjax "true"
      elsif turbo_type
        suffix = "_turbo"
        set_request_turbo turbo_type
        set_request_pjax "false"
      elsif react_navigation_type.present?
        suffix = "_react_#{react_navigation_type}"
        set_request_pjax "false"
      else
        suffix = "_full"
        set_request_pjax "false"
      end
      if logged_in?
        set_request_category "browser#{suffix}", set_datadog_category: false
      else
        set_request_category "anon#{suffix}", set_datadog_category: false
      end
      set_request_category_datadog "browser"
    end
  end

  def react_navigation_type
    return "json" if request.headers["X-React-Router"] == "json"
    return "relay" if request.headers["X-React-Router"] == "relay"
    nil
  end

  # After filter that records the category this request was placed under. Useful
  # when trying to understand what requests are falling under a given category.
  def request_category_log_filter
    category = request_category || "other"
    user_agent = request.user_agent.to_s[0, 40].dup.force_encoding(Encoding::UTF_8).scrub!
    url = "#{request.host_with_port}#{request.path_info}"
    logger.info "Request category: #{category} #{url} \"#{user_agent}...\""
  end

  # for mysql hints.
  # see config/initializers/query_log_tags
  def query_logs_route
    @query_logs_route ||= "%s#%s" % [params[:controller], params[:action]]
  end

  # Returns whether or not it was likely that this request came from a human
  # doing intentional things like clicking links, submitting forms, etc
  def full_navigation_request_category?
    FULL_NAVIGATION_REQUEST_CATEGORIES.include?(request_category)
  end
end
