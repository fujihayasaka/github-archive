# typed: strict
# frozen_string_literal: true

class Sponsors::Webhooks::SecretFieldComponent < ApplicationComponent
  extend T::Sig

  sig { params(hook: Hook).void }
  def initialize(hook:)
    @hook = hook
  end

  private

  sig { returns(Hook) }
  attr_reader :hook

  sig { returns(T::Boolean) }
  def show_secret_banner?
    return false if hook.new_record?
    T.unsafe(hook).secret.present?
  end
end
