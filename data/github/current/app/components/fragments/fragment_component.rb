# typed: true
# frozen_string_literal: true

# View Component for https://github.com/github/fiber-fragments
#
# This is experimental.

module Fragments
  # FragmentComponent creates a <fragment> tag.
  #
  # `src` The source to fetch for replacement in the DOM
  # `method` can be of GET (default) or POST.
  # `primary` denotes a fragment that sets the response code of the page
  # `id` is an optional unique identifier (optional)
  # `refis` an optional forward reference to an `id` (optional)
  # `timeout` timeout of a fragement to receive in milliseconds (default is 300)
  # `deferred` is deferring the fetch to the browser
  # `fallback` is the fallback source in case of timeout/error on the current fragment
  class FragmentComponent < ViewComponent::Base
    def initialize(**system_arguments)
      @system_arguments = system_arguments

      raise ArgumentError, "`src` is a required attribute." if !system_arguments.key?(:src) && !Rails.env.production?

      @content_tag_args = @system_arguments
    end

    def call
      content_tag :fragment, nil, @content_tag_args
    end
  end
end
