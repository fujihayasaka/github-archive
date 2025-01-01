# typed: strict
# frozen_string_literal: true

class Mail::TwitterButtonComponent < ApplicationComponent
  extend T::Sig

  # https://developer.twitter.com/en/docs/twitter-for-websites/tweet-button/guides/web-intent
  TWITTER_WEB_INTENT_URL = "https://twitter.com/intent/tweet"

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
