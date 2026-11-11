# typed: false
# frozen_string_literal: true

module Api::App::SecretsHelpers
  def rescue_from_secrets_errors(rescue_lambda = nil)
    yield
  rescue Secrets::Error => e
    rescue_lambda&.call(e)
    if e.options.present?
      deliver_error!(e.status, e.options)
    else
      deliver_error!(e.status)
    end
  end
end
