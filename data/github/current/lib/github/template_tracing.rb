# typed: true
# frozen_string_literal: true

module GitHub
  class TemplateTracing
    extend T::Sig

    sig { void }
    def initialize
      @current = root
    end

    sig { params(template_name: T.nilable(String)).void }
    def start(template_name)
      rendering = TemplateTracingRenderer.new(template_name)
      rendering.start_time = Time.now
      @current.add(rendering)
      @current = rendering
    end

    sig { params(template_name: T.nilable(String)).void }
    def finished(template_name)
      @current.end_time = Time.now
      @current = @current.parent
    end

    sig { returns(Float) }
    def total_time
      root.child_time
    end

    sig { returns(TemplateTracingRenderer) }
    def root
      return @root if defined?(@root)
      @root = TemplateTracingRenderer.new("root")
    end
  end
end
