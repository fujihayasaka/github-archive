# typed: true
# frozen_string_literal: true

module ApplicationController::AfterResponseDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern

  # Public: Execute a block of code after the HTTP response has been sent to the user, if possible. Otherwise, run it
  # now. This is useful for deferring post-processing code (such as marking something as "read") in such a way that it
  # will have no effect on the user's perception of the page performance.
  #
  # block - Block of code to execute after the HTTP response has been sent to the user.
  #
  # Returns nothing.
  def after_response(&block)
    if GitHub.after_response.enabled?
      if !defined?(@after_response_callbacks)
        @after_response_callbacks = []
        GitHub.after_response.perform(:after_response_callbacks) do
          @after_response_callbacks.each(&:call)
        end
      end

      @after_response_callbacks << block
    else
      block.call
    end
    nil
  end
end
