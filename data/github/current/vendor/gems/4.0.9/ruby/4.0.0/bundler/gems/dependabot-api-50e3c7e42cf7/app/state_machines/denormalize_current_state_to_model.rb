# frozen_string_literal: true

module DenormalizeCurrentStateToModel
  extend ActiveSupport::Concern

  included do
    # Update the current_state and updated_at columns on the model after a transition
    # is created but before the transaction is committed.
    after_transition do |model, transition|
      next unless model.respond_to?(:current_state=) && model.respond_to?(:update!)

      model.update!(current_state: transition.to_state)
    end

    def current_state(force_reload: false)
      return super unless object.is_a?(ApplicationRecord) && object.attributes.key?("current_state")

      if force_reload
        # reload both the model and the storage adapter to ensure they are in sync
        object.reload
        @storage_adapter.reset
      end
      object.attributes["current_state"]
    end

    def after_initialize
      @storage_adapter.extend(DenormalizeCurrentStateToModel::StorageAdapterOverrides)
    end
  end

  module StorageAdapterOverrides
    def reset
      super
      return unless parent_model.is_a?(ApplicationRecord) && parent_model.attributes.key?("current_state")

      parent_model.assign_attributes(current_state: parent_model.class.where(id: parent_model.id).pick(:current_state))
    end
  end
end
