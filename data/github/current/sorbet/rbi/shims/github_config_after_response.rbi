# typed: true

# This file is a manual shim for Sorbet to recognize dynamically defined methods
# in GitHub::Config::AfterResponse. These methods are defined via the self.extended
# callback in lib/github/config/after_response.rb and cannot be automatically inferred
# by Tapioca.

module GitHub
  class << self
    sig { returns(T.nilable(T::Boolean)) }
    def after_response_middleware_enabled; end
    
    sig { returns(T::Boolean) }
    def after_response_middleware_enabled?; end
    
    sig { params(value: T::Boolean).void }
    def after_response_middleware_enabled=(value); end
    
    sig { returns(T.nilable(T::Boolean)) }
    def after_response_raise_on_exception; end
    
    sig { returns(T::Boolean) }
    def after_response_raise_on_exception?; end
    
    sig { params(value: T::Boolean).void }
    def after_response_raise_on_exception=(value); end
  end
end
