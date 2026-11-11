# typed: true
# frozen_string_literal: true

require "set"

module Elastomer
  # Rule-based classifier concern attaching lightweight behavior flags to query objects.
  module Classifier
    # Rule data type for storing rule metadata and predicate.
    Rule = Data.define(:name, :description, :predicate) do
      def match?(ctx) = predicate.call(ctx)
    end

    extend ActiveSupport::Concern

    class_methods do
      def rules
        @rules ||= []
      end

      def rule(name, description = nil, &block)
        return if rules.any? { |r| r.name == name }
        rules << Rule.new(name, description, block)
      end
    end

    def classifications
      @classifications
    end

    def classify!
      @classifications = begin
        matched = Set.new
        klass = T.unsafe(self).class
        if klass.respond_to?(:rules)
          klass.rules.each do |rule|
            matched << rule.name if rule.match?(self)
          end
        end
        matched
      end
    end

    def classified_as?(name)
      !!@classifications&.include?(name)
    end
  end
end
