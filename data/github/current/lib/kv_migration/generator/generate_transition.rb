# typed: true
# frozen_string_literal: true

require "kv_migration/generator/utils"

module KvMigration
  module Generator
    class GenerateTransition
      include KvMigration::Generator::Utils

      TEMPLATE = "lib/github/transitions/templates/kv/transition_template.rb.erb"

      def self.call(service, domain, key_patterns, transition_file: nil)
        new(service, domain, key_patterns, transition_file:).call
      end

      def initialize(service, domain, key_patterns, transition_file: nil)
        @service = service
        @domain = domain
        @key_patterns = escape_key_patterns(key_patterns)
        @transition_file = transition_file || default_transition_path
      end

      def call
        ensure_directory_exists(File.dirname(transition_file))
        write_file(transition_file, render(TEMPLATE, binding))
      end

      def model_name = "#{service.underscore.camelize}KeyValues"
      def class_name = "Move#{model_name}"
      def transition_name = "#{now}_#{class_name.underscore}"
      def table_name = "#{service.underscore}_key_values"
      def default_transition_path = "lib/github/transitions/#{transition_name}.rb"
      def now = Time.now.utc.strftime "%Y%m%d%H%M%S"

      private

      attr_reader :service, :domain, :key_patterns, :transition_file

      def escape_key_patterns(key_patterns)
        key_patterns.map { |k| k.gsub(/(?<!\\\\)_/, '\\\\\\_') }
      end
    end
  end
end
