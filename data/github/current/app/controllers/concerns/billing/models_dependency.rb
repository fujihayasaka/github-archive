# typed: strict
# frozen_string_literal: true

module Billing::ModelsDependency
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { void }
  def render_models_data
    respond_to do |format|
      format.json do
        begin
          response = Billing::Platform::Api::Client.new.get_copilot_models
        rescue => e # rubocop:todo Lint/RescueException
          Failbot.report(e, app: "billing-platform")
          return render json: { error: "Unable to query models", models: [] }, status: 500
        end

        if response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occurred", models: [] }, status: 500
        end

        models_array = response[:models] || []
        formatted_models_array = response[:formatted_models] || []

        combined_models = models_array.map.with_index do |model, index|
          {
            model: model,
            formattedModel: formatted_models_array[index] || model
          }
        end

        render json: { models: combined_models }, status: 200
      end
    end
  end
end
