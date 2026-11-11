# typed: false
# frozen_string_literal: true

# We subclass Pipeline so to_html can return html_safe strings.
module GitHub
  module HTML
    class Pipeline < ::HTML::Pipeline
      # Like call but guarantee the value returned is a string of HTML markup.
      def to_html(input, context = {}, result = nil)
        unless context[:pipeline_run_id]
          context[:pipeline_run_id] = SecureRandom.hex
        end

        GitHub.dogstats.distribution_time("github.html_pipeline.to_html.latency") do
          result = call(input, context, result = nil)
          output = result[:output]

          html = if output.respond_to?(:to_html)
            output.to_html
          else
            output.to_s
          end

          result[:html_safe] ? html.html_safe : html # rubocop:disable Rails/OutputSafety
        end
      end

      def async_to_html(input, context = {}, result = nil)
        Promise.resolve(to_html(input, context, result))
      end
    end
  end
end
