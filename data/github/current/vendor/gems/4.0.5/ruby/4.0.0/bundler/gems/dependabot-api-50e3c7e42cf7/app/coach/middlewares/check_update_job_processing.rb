# frozen_string_literal: true

require "renderer"

module Middlewares
  class CheckUpdateJobProcessing < Coach::Middleware
    requires :update_job

    def call
      return update_job_not_yet_accessed unless update_job_ever_accessed?
      return Renderer.no_content unless update_job_processing?

      next_middleware.call
    end

    private

    def update_job_ever_accessed?
      update_job.history.to_a.reverse.
        take_while { |t| t.to_state.to_sym != :pending_retry }.
        any? { |t| t.to_state.to_sym == :processing }
    end

    def update_job_processing?
      update_job.in_state?(:processing)
    end

    def update_job_not_yet_accessed
      Renderer.render_error(
        status: 400,
        title: "Bad Request",
        detail: "Update job should have been transitioned to `processing` " \
                "to reach here, but hasn't been",
      )
    end
  end
end
