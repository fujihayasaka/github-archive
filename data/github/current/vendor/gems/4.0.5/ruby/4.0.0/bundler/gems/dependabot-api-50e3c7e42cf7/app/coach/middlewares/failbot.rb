# frozen_string_literal: true

module Middlewares
  class Failbot < Coach::Middleware
    def call
      ::Dependabot::Exceptions.push(transaction: config[:route_class]&.to_s)

      next_middleware.call
    end
  end
end
