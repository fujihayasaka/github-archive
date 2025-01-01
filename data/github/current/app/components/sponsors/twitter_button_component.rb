# typed: strict
# frozen_string_literal: true

class Sponsors::TwitterButtonComponent < ApplicationComponent
  include SvgHelper

  sig do
    params(
      sponsorable_login: String,
      label: T.nilable(String),
      text: T.nilable(String),
      data: T::Hash[String, T.untyped],
      url_params: T::Hash[String, T.untyped],
      render_textarea: T::Boolean,
      autofocus: T::Boolean,
      system_arguments: Primer::SystemArgumentsValue
    ).void
  end
  def initialize(
    sponsorable_login:,
    label: "Post on X",
    text: "",
    data: {},
    url_params: {},
    render_textarea: false,
    autofocus: false,
    **system_arguments
  )
    @sponsorable_login = sponsorable_login
    @label = label
    @text = text
    @data = data
    @url_params = url_params
    @render_textarea = render_textarea
    @autofocus = autofocus
    weight = T.cast((system_arguments[:font_weight] || :normal), Symbol)
    @font_weight = T.let(weight, Symbol)
    @system_arguments = system_arguments
  end

  private

  # We use query params to know whether a Sponsors profile page view came from Twitter or not
  # and how it was shared (e.g. the sponsorable, the sponsor, etc.)
  #
  #  `sc` - stands for "source" and `t` represents Twitter
  sig { returns String }
  def sponsors_profile_url
    query_params = @url_params.merge(
      Sponsors::TrackingParameters.new(
        source: Sponsors::TrackingParameters::TWITTER_SOURCE,
      ).to_h
    ).to_query

    "https://github.com/sponsors/#{@sponsorable_login}?#{query_params}"
  end
end
