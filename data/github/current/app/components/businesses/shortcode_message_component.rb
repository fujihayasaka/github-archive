# typed: true
# frozen_string_literal: true

class Businesses::ShortcodeMessageComponent < ApplicationComponent
  attr_reader :shortcode, :already_taken, :error_message

  def initialize(shortcode:, already_taken: false, error_message: nil)
    @shortcode = shortcode
    @already_taken = already_taken
    @error_message = error_message
  end

  private

  def already_taken?
    already_taken
  end
end
