# typed: true
# frozen_string_literal: true

module GitHub
  module Memoizer
    extend T::Helpers

    VALID_MEMOIZED_METHOD_NAME_REGEX = /\A[_A-Za-z]\w*\??\z/

    module ClassMethods
      extend T::Helpers

      requires_ancestor { Module }

      def memoize(method_name)
        all_instance_methods = instance_methods + private_instance_methods + protected_instance_methods
        raise ArgumentError, "bang methods cannot be memoized" if method_name.end_with?("!")
        raise ArgumentError, "method must be a valid unescaped method name" unless VALID_MEMOIZED_METHOD_NAME_REGEX.match?(method_name)
        raise ArgumentError, "method must be an instance method" unless all_instance_methods.include?(method_name)

        method = instance_method(method_name)
        sig = T::Private::Methods.signature_for_method(method)
        method = sig.nil? ? method : sig.method

        raise ArgumentError, "methods with arguments can not be memoized" if method.arity != 0
        raise ArgumentError, "methods in singleton classes can not be memoized" if singleton_class?

        if !const_defined?(:MemoizedMethods, false)
          const_set(:MemoizedMethods, Module.new)
          prepend const_get(:MemoizedMethods)
        end

        visibility = if private_method_defined?(method_name)
          :private
        elsif protected_method_defined?(method_name)
          :protected
        else
          :public
        end

        location = T.must(T.must(caller_locations(1, 1)).first)

        const_get(:MemoizedMethods).module_eval <<-RUBY, location.path, location.lineno
          def #{method_name}
            @all_memoized ||= {}
            value = :"#{method_name}"
            return @all_memoized[value] if @all_memoized.key?(value)
            @all_memoized[value] = super
          end
        RUBY

        const_get(:MemoizedMethods).send(visibility, method_name) if visibility != :public
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
