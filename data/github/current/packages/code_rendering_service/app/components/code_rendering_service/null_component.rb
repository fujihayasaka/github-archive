# typed: true
# frozen_string_literal: true

module CodeRenderingService
  # A null object that can be used to represent code that is not supported by a known redering service
  class NullComponent < CodeRenderingService::BaseComponent

    def initialize
      @view_type = :unsupported
      @render_type = nil
    end

    sig { returns(T::Boolean) }
    def supports_view?
      false
    end

    sig { returns(NilClass) }
    def render_type
      nil
    end
  end
end
