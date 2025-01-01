# typed: true
# frozen_string_literal: true

class Oauth::SuggestedSignInComponent < ApplicationComponent
  def initialize(application:, original_url:, raw_suggestion:)
    @application = application
    @original_url = original_url
    @raw_suggestion = raw_suggestion
  end

  def render?
    return false if @raw_suggestion.blank?
    return false if @raw_suggestion == current_user.display_login

    suggested_login.present?
  end

  memoize def suggested_login
    # Save loading a User object into memory
    return unless User::LOGIN_REGEX.match?(@raw_suggestion)
    return unless User.find_by_login(@raw_suggestion)

    @raw_suggestion
  end
end
