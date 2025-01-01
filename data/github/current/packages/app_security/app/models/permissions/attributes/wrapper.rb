# typed: strict
# frozen_string_literal: true

module Permissions
  module Attributes
    module Wrapper
      extend T::Helpers
      extend T::Sig
      requires_ancestor { Object }

      module ClassMethods
        extend T::Sig

        sig { params(permissions_wrapper_class: T.class_of(Permissions::Attributes::Default)).void }
        attr_writer :permissions_wrapper_class

        sig { returns(T.class_of(Permissions::Attributes::Default)) }
        def permissions_wrapper_class
          @permissions_wrapper_class ||= T.let(Permissions::Attributes::Default, T.nilable(T.class_of(Permissions::Attributes::Default)))
        end
      end

      sig { returns(Permissions::Attributes::Default) }
      def permissions_wrapper
        T.cast(self.class, ClassMethods).permissions_wrapper_class.new(self)
      end

      mixes_in_class_methods(ClassMethods)
    end
  end
end
