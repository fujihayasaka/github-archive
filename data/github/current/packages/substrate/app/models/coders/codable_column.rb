# typed: strict
# frozen_string_literal: true

module Coders
  module CodableColumn
    extend T::Helpers
    extend T::Sig

    module ClassMethods
      extend T::Helpers
      extend T::Sig
      requires_ancestor { T.class_of(::ActiveRecord::Base) }

      sig { params(field: Symbol, coder_class: T.class_of(Coders::Base), delegate_target: Symbol).void }
      def serialize_with_coder(field, coder_class, delegate_target = field)
        serialize_field(field, Coders::Handler.new(coder_class), delegate_target)
      end

      sig { returns(T::Hash[Symbol, ::Coders::Handler]) }
      def enabled_coders
        @enabled_coders ||= T.let({}, T.nilable(T::Hash[Symbol, ::Coders::Handler]))
      end

      private

      sig { params(field: Symbol, handler: Coders::Handler, delegate_target: Symbol).void }
      def serialize_field(field, handler, delegate_target)
        serialize field, coder: handler
        enabled_coders[field] = handler
        coder_class = handler.send(:coder)
        delegate *coder_class.members, to: delegate_target
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
