# typed: true
# frozen_string_literal: true

module ActionController
  module Head
    alias :original_head :head

    sig { params(status: T.any(Integer, Symbol), options: T.nilable(Hash)).returns(T::Boolean) }
    def head(status, options = nil)
      if @_response_body
        err = ::AbstractController::DoubleRenderError.new
        err.set_backtrace(Kernel.caller)
        Failbot.report!(err)

        @_response_body = nil
      end

      original_head(status, options)
    end
  end
end
