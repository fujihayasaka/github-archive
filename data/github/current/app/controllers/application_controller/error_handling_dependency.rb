# typed: false
# frozen_string_literal: true

module ApplicationController::ErrorHandlingDependency
  extend ActiveSupport::Concern

  class NotFound < StandardError; end
  class CookiesRequired < StandardError; end
  class BadRedirect < StandardError; end

  included do
    # NOTE: This rescue_from must come first as the global catch-all
    rescue_from Exception, with: :handle_generic_exception

    rescue_from NotFound do |e|
      render_404(e)
    end

    rescue_from WillPaginate::InvalidPage, with: :render_404

    rescue_from ActiveRecord::RecordNotFound do |e|
      # log a needle just in case anything goes awry and we get an unusually large number of these
      Failbot.report_user_error(e)
      render_404(e)
    end

    rescue_from ActionController::UnknownFormat do
      # we have to do this manually now because Rails will throw a
      # DoubleRenderError if we try to call `head(:not_acceptable)` here
      # https://github.com/github/github/pull/371615#issuecomment-2797250608
      response.reset_body!
      response.status = :not_acceptable
    end

    rescue_from BERTRPC::ConnectionError, BERTRPC::ProtocolError, BERTRPC::ReadTimeoutError do |e|
      failbot(e)
      render "repositories/states/down"
    end

    rescue_from Search::Query::MaxOffsetError do
      render_404
    end

    rescue_from BERTRPC::ProxyError do |e|
      case e.message
      when /storage server .* offline/i
        # the file server is marked offline
        render "repositories/states/down"
      when /No route found for/i
        # assume the repository is being moved
        failbot(e)
        render "repositories/states/moving"
      else
        # something crazy
        failbot(e)
        render "repositories/states/down"
      end
    end

    rescue_from ActionView::TemplateError do |e|
      if (Rails.env.production? || Rails.env.staging?) &&
          e.cause.kind_of?(ActionController::RoutingError)
        failbot(e.cause)
        render_optional_error_file response_code_for_rescue(e)
      elsif cause = e.cause
        rescue_with_handler(cause) || handle_generic_exception(cause)
      else
        handle_generic_exception(cause)
      end
    end

    unless Rails.env.development?
      rescue_from ActionView::MissingTemplate do
        GitHub.dogstats.increment("errors.action_view_missing_template")
        head(:not_acceptable)
      end
    end

    # See #handle_unverified_request for our selective failbot calls
    rescue_from ActionController::InvalidAuthenticityToken do |e|
      if cookies.count == 0
        GitHub.dogstats.increment("errors.csrf_invalid", tags: ["reason:no_cookies", "logged_in:#{logged_in?}"])
        render plain: "Cookies must be enabled to use GitHub.", status: 403
      else
        if request_authenticity_tokens.all?(&:blank?)
          GitHub.dogstats.increment("errors.csrf_invalid", tags: ["reason:no_tokens", "logged_in:#{logged_in?}"])
        elsif request_authenticity_tokens.none?(&method(:properly_encoded_csrf_token?))
          GitHub.dogstats.increment("errors.csrf_invalid", tags: ["reason:invalid_token_format", "logged_in:#{logged_in?}"])
        else
          GitHub.dogstats.increment("errors.csrf_invalid", tags: ["reason:invalid_token_value", "logged_in:#{logged_in?}"])
        end

        render_optional_error_file response_code_for_rescue(e)
      end
    end

    rescue_from ActionController::InvalidCrossOriginRequest do |e|
      render_optional_error_file response_code_for_rescue(e)
    end
  end

  def render_404(exception = nil)
    # Make sure we don't leak any data from an object the user cannot see:
    # https://github.com/github/github/issues/110772.
    clear_current_repository

    if request.format.try(:html_fragment?)
      head :not_found, content_type: Mime[:html_fragment]
    elsif request.format.try(:html?)
      layout = gist_request? ? "gists" : "site"
      render "error/404", layout: layout, status: :not_found, formats: [:html]
    elsif request.format.try(:js?) || request.format.try(:json?)
      set_static_file_csp
      render json: { error: "Not Found" }, status: :not_found
    else
      set_static_file_csp
      render plain: "Not Found", status: :not_found
    end
    true
  end

  def render_email_verification_required(message: "Sorry, you need to verify at least one email address first.")
    if request.format.try(:html?)
      GitHub.dogstats.increment "user_email", tags: ["action:verification_required", "response:redirect"]
      redirect_to unverified_email_path
    else
      respond_to do |format|
        format.json do
          GitHub.dogstats.increment "user_email", tags: ["action:verification_required", "response:forbidden.json"]
          render json: { error: message }, status: :forbidden
        end
        format.all do
          GitHub.dogstats.increment "user_email", tags: ["action:verification_required", "response:forbidden.other_non_html_format"]
          render plain: message, status: :forbidden
        end
      end
    end
  end

  # Public: Given the result of a GraphQL query that had errors, determine if a 404 page should be
  # shown.
  #
  # Returns a Boolean.
  def should_graphql_404?(data)
    error_key = data.errors.keys&.first
    error_type = data.errors.details[error_key]&.first["type"]
    %w[NOT_FOUND FORBIDDEN].include?(error_type)
  end

  # Public: Given the result of a GraphQL query that had errors, set a flash message with
  # a description of the errors.
  def flash_graphql_error(data)
    error_key = data.errors.keys&.first
    error_messages = data.errors.messages[error_key]
    flash[:error] = error_messages.to_sentence
  end

  # Public: Given the result of a GraphQL query that had errors, either render a 404 response
  # or render an error message in JSON or plain text as appropriate.
  def render_graphql_error(data, active_model_errors_format: true)
    return render_404 if should_graphql_404?(data)

    error_key = data.errors.keys&.first
    error_messages = data.errors.messages[error_key]
    if request.format.try(:js?) || request.format.try(:json?)
      payload = active_model_errors_format ? { errors: error_messages } : error_messages.first
      render json: payload, status: :unprocessable_entity
    else
      render plain: error_messages.to_sentence, status: :unprocessable_entity
    end
  end

  protected

  def handle_generic_exception(e)
    log_error(e)
    GitHub::GracefulDegradationInstrumenter.unhandled_exception = e

    Failbot.push("gh.exception.is_critical": true)
    failbot(e)

    if Rails.env.test? || Rails.env.development?
      raise e
    else
      render_optional_error_file(response_code_for_rescue(e))
    end
  end

  private

  def log_error(exception)
    logger.fatal(
      "\n#{exception.class} (#{exception.message}):\n  " +
      exception.backtrace.join("\n  ") + "\n\n",
    )
  end

  def properly_encoded_csrf_token?(token)
    return false unless token.is_a?(String) && token.present?
    decoded_masked_token = decode_csrf_token(token)
    # masked tokens are twice their unmasked length since they are
    # a combination of one_time_pad || real_token
    decoded_masked_token.length == ActionController::RequestForgeryProtection::AUTHENTICITY_TOKEN_LENGTH * 2
  rescue ArgumentError # invalid Base64
    false
  end
end
