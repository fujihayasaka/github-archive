# typed: true
# frozen_string_literal: true

class Hook
  module ConfigAccessor
    extend ActiveSupport::Concern
    extend T::Helpers

    module ClassMethods
      def config_accessor(*attrs)
        T.unsafe(self).config_reader *attrs
        T.unsafe(self).config_writer *attrs
      end

      def config_reader(*attrs)
        attrs.each do |attr|
          T.unsafe(self).define_method attr do
            T.unsafe(self).config[attr.to_s]
          end
        end
      end

      def config_writer(*attrs)
        attrs.each do |attr|
          T.unsafe(self).define_method :"#{attr}=" do |value|
            T.unsafe(self).update_existing_config(attr.to_s => value)
          end
        end
      end
    end
  end
end
