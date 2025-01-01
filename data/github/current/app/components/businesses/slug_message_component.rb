# typed: true
# frozen_string_literal: true

class Businesses::SlugMessageComponent < ApplicationComponent
  attr_reader :slug, :already_taken, :error_message

  def initialize(slug:, already_taken: false, error_message: nil)
    @slug = slug
    @already_taken = already_taken
    @error_message = error_message
  end

  private

  def already_taken?
    already_taken
  end
end
