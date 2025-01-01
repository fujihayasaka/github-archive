# typed: true
# frozen_string_literal: true

module GitHub
  module Unsullied
    class Editor
      def initialize(object_name)
        @object_name = object_name

        @fields = {
          name: {},
          format: {},
          body: {},
          commit: {},
          preview: {},
          submit: {},
        }
      end

      def add_params(name, params)
        @fields[name].merge! params
      end

      def name_for(name)
        "#{@object_name}[#{name}]"
      end

      def value_for(name)
        param_for name, :value
      end

      def param_for(name, key)
        @fields.fetch(name, {})[key]
      end

      def options_for(name, options = {})
        params_for(name).except(:value).merge options
      end

      def has_params_for?(name)
        @fields[name].present?
      end

      private

      def params_for(name)
        @fields[name] || {}
      end
    end
  end
end
