# frozen_string_literal: true

require "renderer"

module Routes
  module AutofixSuggestionJobs
    class UploadSarif < Coach::Middleware
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckAutofixToken

      requires :autofix_job

      def call
        SubmitSarif.new(sarif_contents: request.raw_post, autofix_job: autofix_job).run
        Renderer.no_content
      end
    end
  end
end
