# typed: strict
# frozen_string_literal: true

class Closables::Buttons::CloseComponent < Closables::Buttons::BaseComponent
  extend T::Sig

  private

  sig { returns(T::Boolean) }
  def render?
    closable.open?
  end

  sig { returns(String) }
  def default_close_text
    "Close #{closable_name}"
  end
end
