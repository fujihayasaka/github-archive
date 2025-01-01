# typed: true
# frozen_string_literal: true

module Platform
  module Models
    class RepositoryCodeownersError
      attr_reader :codeowners, :error
      delegate :repository, :path, to: :codeowners

      def initialize(codeowners, error)
        @codeowners = codeowners
        @error = error
      end

      def respond_to_missing?(name, include_private = false)
        @error.respond_to?(name, include_private) || super
      end

      def method_missing(name, *args, **kwargs)
        if @error.respond_to?(name)
          @error.public_send(name, *args, **kwargs)
        else
          super
        end
      end
    end
  end
end
