# typed: true
# frozen_string_literal: true

class Businesses::SubdomainMessageComponent < ApplicationComponent
  attr_reader :subdomain, :error_message

  def initialize(subdomain:, error_message: nil)
    @subdomain = subdomain
    @error_message = error_message
  end
end
