# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Authorization::ReauthorizeScopedObjects
  extend ActiveSupport::Concern
  include ::Platform

  included do |base|
    if !base.ancestors.include?(Platform::Objects::Base)
      raise Platform::Errors::Internal, "ReauthorizeScopedObjects can only be included in classes that inherit from Platform::Objects::Base, /
        and #{base} is not."
    end

    def self.scope_items(items, context)
      # we want to limit this, for now, to persisted queries
      return items.clone if !reauthorize_scoped_objects && context[:viewer]&.feature_enabled?(:graphql_skip_reauthorize_scoped_items)
      items
    end

    reauthorize_scoped_objects(false)
  end
end
