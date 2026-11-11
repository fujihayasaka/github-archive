# typed: true
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # A vexi actor representing a `Processor::Base` subclass, so that feature
    # flags scoped to processor behavior can be targeted at all instances of a
    # particular processor class with a single shared flag name.
    #
    # Example:
    #
    #   actor = MemexProjectColumn::Interface::Indexable::Processor::ParentIssueProjectChange.processor_class_actor
    #   FeatureFlag.vexi.enabled?(:projects_any_match_helper, actor, default: false)
    class ClassActor
      include GitHub::VexiActor

      def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
        new(id.to_s)
      end

      def initialize(klass)
        @klass = klass
      end

      def id
        @klass.to_s
      end
    end
  end
end
