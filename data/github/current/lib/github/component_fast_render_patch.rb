# typed: true
# frozen_string_literal: true

# Because the GitHub::FastRenderEnhancer replaces `render` calls in views with
# their compiled method names, we need to use `method_missing` to catch that
# method call then delegated it to @view_context via `_run`. Without this, the
# compiled method name of the partial will be called on the component and raise
# a method missing exception.
module GitHub
  module ComponentFastRenderPatch
    def method_missing(name, *args, &block)
      if name.start_with?("_app_views")
        @view_context._run(name, self, args.first, @output_buffer, &block)
      else
        super
      end
    end
  end
end
