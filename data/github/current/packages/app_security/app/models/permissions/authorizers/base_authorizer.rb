# typed: true
# frozen_string_literal: true

module Permissions
  module Authorizers
    class BaseAuthorizer
      def authorize(request:)
        raise NotImplementedError.new("#authorize should be implemented by subclasses")
      end
    end
  end
end
