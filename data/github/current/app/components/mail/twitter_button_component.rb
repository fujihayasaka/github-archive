# typed: strict
# frozen_string_literal: true

class Mail::TwitterButtonComponent < ApplicationComponent
  sig do
    params(
      text: T.nilable(String),
    ).void
  end
  def initialize(
    text: ""
  )
    @text = text
  end
end
