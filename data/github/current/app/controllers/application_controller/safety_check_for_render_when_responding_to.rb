# typed: false
# frozen_string_literal: true

module ApplicationController::SafetyCheckForRenderWhenRespondingTo
  if !Rails.env.production?
    class RenderToStringCalledWithoutFormatsError < StandardError
      def message
        msg = "\n\n" + <<~ENDMESSAGE
        `render_to_string` was called within a `respond_to` block but
        no `formats:` option was passed. Always specify `formats:`
        when calling `render_to_string` within a `respond_to` block.
        ENDMESSAGE
      end
    end

    def render_to_string(*args)
      within_respond_to = caller.any? do |line|
        line.match(/respond_to/) && line.match(/mime_responds\.rb/)
      end
      if within_respond_to
        opts = args.find { |arg| arg.kind_of?(Hash) }
        unless opts && opts.is_a?(Hash) && opts.key?(:formats)
          raise RenderToStringCalledWithoutFormatsError.new
        end
      end
      super
    end
  end
end
