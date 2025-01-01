# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedWorkSearchFormComponent < ApplicationComponent
  def initialize(sponsorable_login:)
    @sponsorable_login = sponsorable_login
  end

  private

  def render?
    @sponsorable_login.present?
  end
end
