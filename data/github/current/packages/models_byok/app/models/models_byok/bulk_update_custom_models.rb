# typed: true
# frozen_string_literal: true

module ModelsByok
  class BulkUpdateCustomModels
    sig do
      params(
        updates: T::Array[{ id: Integer, copilot_chat_enabled: T::Boolean }],
        actor: User,
        org: Organization
      ).returns(T::Boolean)
    end
    def self.call(updates, actor:, org:)
      new(updates, actor: actor, org: org).call
    end

    sig do
      params(
        updates: T::Array[{ id: Integer, copilot_chat_enabled: T::Boolean }],
        actor: User,
        org: Organization
      ).void
    end
    def initialize(updates, actor:, org:)
      @updates = updates
      @actor = actor
      @org = org
    end

    sig { returns T::Boolean }
    def call
      return false unless valid?
      process_updates
    end

    private

    sig { returns T::Hash[Integer, CustomModel] }
    def custom_models_by_id
      return @custom_models_by_id if @custom_models_by_id
      ids = @updates.map { |hash| hash[:id] }
      custom_models = @org.custom_models.includes(:custom_key).where(id: ids).to_a
      custom_models.each { |custom_model| custom_model.actor = @actor }
      @custom_models_by_id = custom_models.index_by(&:id)
    end

    sig { returns T::Boolean }
    def valid?
      # Ensure only the specified organization's custom models would be updated:
      @updates.size == custom_models_by_id.size
    end

    sig { returns T::Boolean }
    def process_updates
      ModelsByok::CustomModel.transaction do
        @updates.each do |models_params|
          id = models_params[:id].to_i
          custom_model = custom_models_by_id[id]
          custom_model&.update!(models_params.except(:id))
        end
      end

      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
      false
    end
  end
end
