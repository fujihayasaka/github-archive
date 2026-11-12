require "rails_helper"

RSpec.describe CheckpointsController, type: :controller do
  describe "checkpointing" do
    it "stores checkpoints" do
      post :checkpoint, params: { id: "npm_sink" }
      expect(parsed_response[:value]).to eq(0)

      get :checkpoint, params: { id: "npm_sink" }
      expect(parsed_response[:value]).to eq(0)

      put :set_checkpoint, params: { id: "npm_sink", value: 10 }
      expect(parsed_response[:value]).to eq(10)
    end

    it "returns an error when values are invalid" do
      put :set_checkpoint, params: { id: "npm_sink", value: "NaN" }
      expect(response.status).to eq(422)

      put :set_checkpoint, params: { id: "npm_sink", value: nil }
      expect(response.status).to eq(422)
    end
  end

  def parsed_response
    JSON.parse(response.body).with_indifferent_access
  end
end
