require "rails_helper"

describe Checkpoint do
  describe ".with_name" do
    it "returns checkpoints with the specified name" do
      included = described_class.create!(name: "checkpoint_1")
      excluded = described_class.create!(name: "checkpoint_2")

      expect(described_class.with_name("checkpoint_1")).to eq [included]
    end
  end
  describe ".names" do
    it "returns the names of all checkpoints" do
      described_class.create!(name: "checkpoint_1")
      described_class.create!(name: "checkpoint_2")

      expect(described_class.names).to eq ["checkpoint_1", "checkpoint_2"]
    end
  end

  describe "#reset" do
    it "resets the last checkpointed ID to zero" do
      checkpoint = described_class.create!({
        name: "checkpoint_1",
        last_checkpointed_id: 10
      })

      checkpoint.reset!

      expect(checkpoint.last_checkpointed_id).to eq 0
      expect(checkpoint.reload.last_checkpointed_id).to eq 0
    end
  end

  describe "#set!" do
    it "sets the last checkpointed ID" do
      checkpoint = described_class.create!(name: "checkpoint_1")

      checkpoint.set!(100)

      expect(checkpoint.last_checkpointed_id).to eq 100
      expect(checkpoint.reload.last_checkpointed_id).to eq 100
    end
  end

  describe "#get" do
    it "returns the last checkpointed ID" do
      checkpoint = described_class.create!({
        name: "checkpoint_1",
        last_checkpointed_id: 100
      })

      expect(checkpoint.get).to eq 100
    end
  end
end
