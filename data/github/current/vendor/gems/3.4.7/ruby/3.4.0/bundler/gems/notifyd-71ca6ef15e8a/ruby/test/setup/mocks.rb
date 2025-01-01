# typed: false
# frozen_string_literal: true

require "mocha/minitest"
require "minitest/mock"
require "sorbet-runtime"

# Sorbet can't find this .configure method in Mocha, but we don't need to enable types in this file anyway
Mocha.configure do |c|
  c.stubbing_non_existent_method = :prevent
end

module TypedMocks
  extend T::Sig

  # Use this method to ensure Sorbet understands #stubs in an object
  #
  # @example
  #   Faraday.stubs(:default_adapter) # Type error: Method `stubs` does not exist on `T.class_of(Faraday)`
  #
  #   mockable(Faraday).stubs(:default_adapter) # Sorbet is now happy
  sig {
    type_parameters(:T)
      .params(obj: T.type_parameter(:T))
      .returns(T.all(T.type_parameter(:T), Mocha::ObjectMethods))
  }
  def mockable(obj)
    case obj
    when Mocha::ObjectMethods
      obj
    else
      raise "Mocha is not enabled"
    end
  end
end
