# typed: true
# frozen_string_literal: true

# This base class provides the interface for defining and interacting with a Service's
# options hash generically. Each specific service can implement a sublcass to specify
# their feature's options, validation and defaults.
#
module SecurityProduct
  class Service
    class Options
      include ActiveModel::API
      include ActiveModel::Serializers::JSON

      def self.options
        @options ||= {}
      end

      def self.option(name, default: nil)
        options[name] = { default: default }

        define_method(name) do
          return default unless instance_variable_defined?("@#{name}")

          instance_variable_get("@#{name}")
        end

        define_method("#{name}=") do |value|
          instance_variable_set("@#{name}", value)
        end
      end

      def self.as_params
        options.keys
      end

      # In the event that a child class needs to deprecate an option value that may be persisted
      # in a SecurityConfiguration, overriding this method and explicitly mapping the
      # deprecated version to the default or a replacement is preferred over backfilling
      # configurations.
      #
      # This method is invoked via `before_validation`, so any deprecated values will be
      # removed or updated the next time a SecurityConfiguration is updated.
      def self.new_from_hash(opts)
        filtered_opts = opts ? opts.symbolize_keys.slice(*options.keys) : {}
        new(filtered_opts)
      end

      # This method is used by SecurityConfiguration when persisting a set of options for a
      # feature to ensure that any superfluous keys are removed and default values are
      # injected for any absent keys.
      def self.before_validation(opts)
        new_from_hash(opts).attributes
      end

      def attributes
        self.class.options.each_with_object({}) do |(opt, conf), attrs|
          value = instance_variable_defined?("@#{opt}") ? instance_variable_get("@#{opt}") : conf[:default]
          attrs[opt.to_s] = value
        end
      end

      def self.default_attributes
        options.each_with_object({}) do |(opt, conf), attrs|
          attrs[opt.to_s] = conf[:default]
        end
      end
    end
  end
end
