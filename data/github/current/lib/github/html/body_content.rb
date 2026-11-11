# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Public: Runs a String of content through an HTML processing pipeline,
  # providing easy access to a generated DocumentFragment.
  class BodyContent
    include Scientist
    # Public: Initialize a BodyContent.
    #
    # body     - A String body.
    # context  - A Hash of context options for the filters.
    # pipeline - A GitHub::HTML::Pipeline object with one or more Filters.
    def initialize(body, context, pipeline, use_science = false)
      @body = body
      @context = context
      @pipeline = pipeline
      @use_science = use_science
    end

    # Public: Gets the memoized result of the body content as it passed through
    # the Pipeline.
    #
    # Returns a Hash, or something similar as defined by @pipeline.result_class.
    def result
      async_result.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def async_result
      return @async_result if defined?(@async_result)
      @async_result = if @pipeline.respond_to?(:async_call)
        @pipeline.async_call @body, @context
      else
        Platform::LoaderTracker.ignore_association_loads do
          Promise.resolve(@pipeline.call(@body, @context))
        end
      end
    end

    # Public: Gets the updated body from the Pipeline result.
    #
    # Returns a String or DocumentFragment, or a Promise containing either if
    # the underlying pipeline is async.
    def output
      async_output.sync
    end

    def async_output
      async_result.then { |result| result[:output] }
    end

    # Public: Parses the output into a DocumentFragment.
    #
    # Returns a DocumentFragment.
    def document
      async_document.sync
    end

    def async_document
      async_output.then { |output| GitHub::HTML.parse output }
    end
  end
end
