# frozen_string_literal: true

class ExceptionsController < ActionController::API
  def render_exception
    render json: json_exception, status: status
  rescue Exception
    Rails.logger.error(
      exception&.message
    )
    Rails.logger.error(
      exception&.backtrace&.join("\n")
    )
    render json: failsafe_json, status: 500
  end

  private

  # JSON API error format. See http://jsonapi.org/format/#errors for details.
  def json_exception
    {
      errors: [
        {
          status: status,
          title: title,
        },
      ],
    }.to_json
  end

  def exception
    request.env["action_dispatch.exception"]
  end

  def status
    ActionDispatch::ExceptionWrapper.new(request.env, exception).status_code
  end

  def title
    ActionDispatch::ExceptionWrapper.
      rescue_responses[exception.class.name].
      to_s.titlecase
  end

  def message
    exception.message
  end

  def failsafe_json
    "{\"errors\":[{\"status\":500,\"title\":\"Internal Server Error\"}]}"
  end
end
