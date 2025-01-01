# typed: true
# frozen_string_literal: true

module ModelsByok
  class BulkUpdateCustomModels
    sig do
      params(
        updates: T::Array[{ id: Integer, copilot_chat_enabled: T::Boolean }],
        org: Organization
      ).returns(T::Boolean)
    end
    def self.call(updates, org:)
      new(updates, org: org).call
    end

    sig { params(updates: T::Array[{ id: Integer, copilot_chat_enabled: T::Boolean }], org: Organization).void }
    def initialize(updates, org:)
      @updates = updates
      @org = org
    end

    sig { returns T::Boolean }
    def call
      return false unless valid?
      process_updates
    end

    private

    sig { returns T::Boolean }
    def valid?
      # Ensure only the specified organization's custom models would be updated:
      @updates.size == @org.custom_models.where(id: @updates.map { |m| m[:id] }).count
    end

    sig { returns T::Boolean }
    def process_updates
      ModelsByok::CustomModel.transaction do
        @updates.each do |models_params|
          @org.custom_models.update!(models_params[:id], models_params.except(:id))
        end
      end

      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
      false
    end
  end
end
