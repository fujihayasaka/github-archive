# typed: false
# frozen_string_literal: true

module Repositories
  class ForkButtonComponent < ApplicationComponent
    include RepositoryAnalyticsHelper # for data attributes
    include UsersHelper # for social_count

    # repository - The repository to be forked
    # forkability_error_message - The String to display as an error message if forking is not available for this
    #   repository, or `nil` if forking is allowed.
    # icon_button - A Boolean indicating whether the button should be rendered as an icon button
    def initialize(repository:, forkability_error_message:, icon_button: false)
      @repository = repository
      @forkability_error_message = forkability_error_message
      @icon_button = icon_button
    end

    private

    attr_reader :repository, :forkability_error_message

    def icon_button?
      @icon_button
    end

    def forking_allowed?
      forkability_error_message.nil?
    end

    def must_choose_destination?
      current_user&.organizations&.any? && !current_user&.must_verify_email?
    end

    def button_component(**params)
      return Primer::Beta::IconButton.new(**params) if icon_button?
      Primer::ButtonComponent.new(**params.deep_merge({ aria: { label: nil } }))
    end

    def button_id
      icon_button? ? "fork-icon-button" : "fork-button"
    end

    def button_test_selector(selector)
      icon_button? ? "#{selector}-icon-button" : "#{selector}-button"
    end

    class CounterComponent < ApplicationComponent
      def initialize(repository:)
        @repository = repository
      end

      def call
        render(Primer::Beta::Counter.new(
          id: "repo-network-counter",
          count: @repository.forks_count,
          round: true,
          limit: nil,
          data: {
            pjax_replace: true,
            turbo_replace: true,
          },
        ))
      end
    end
  end
end
