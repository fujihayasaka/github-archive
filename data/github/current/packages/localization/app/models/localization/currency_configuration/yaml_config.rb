# typed: true
# frozen_string_literal: true

module Localization
  module CurrencyConfiguration
    class YamlConfig
      ConfigNotFound = Class.new(StandardError)

      def initialize
        @config_file = Rails.root.join("config/money.yml")
        @config = YAML.safe_load_file(@config_file, aliases: true).deep_symbolize_keys
      end

      def lookup(money)
        code = money.currency.iso_code.to_sym
        @config.fetch(code) do
          raise ConfigNotFound.new("Could not find currency by iso code '#{code}'")
        end
      end

      def all_currencies
        @config.keys.map(&:to_s).reject { |k, _| k.length > 3 }
      end
    end
  end
end
