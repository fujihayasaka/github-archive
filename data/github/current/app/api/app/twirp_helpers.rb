# typed: false
# frozen_string_literal: true

module Api::App::TwirpHelpers
  # Given a block that returns a TwirpResponse,
  # this method returns the value of the response if the response was successful
  # or delivers an API error if the response was not successful
  def handle_twirp_errors
    result = yield

    return result.value if result.call_succeeded?
    if result.options.present?
      deliver_error!(result.status, result.options)
    else
      deliver_error!(result.status)
    end
  end
end
