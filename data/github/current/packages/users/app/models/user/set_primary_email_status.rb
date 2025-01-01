# typed: true
# frozen_string_literal: true

# Public: A response is created when we attempt to set the user's primary email address.
class User::SetPrimaryEmailStatus

  def initialize(invalid_model: nil)
    @invalid_model = invalid_model
    freeze
  end

  def error
    @invalid_model.errors.full_messages.to_sentence
  end

  def error?
    !success?
  end
  alias_method :failure?, :error?

  def success?
    @invalid_model.nil?
  end

  def raise_on_error!
    if error?
      GitHub.logger.error(
        exception: ActiveRecord::RecordInvalid.new(@invalid_model),
        "code.namespace": self.class.name,
        "code.function": "raise_on_error!",
        "gh.validation_errors": error,
      )

      raise ActiveRecord::RecordInvalid.new
    end
  end

  SUCCESS = new
end
