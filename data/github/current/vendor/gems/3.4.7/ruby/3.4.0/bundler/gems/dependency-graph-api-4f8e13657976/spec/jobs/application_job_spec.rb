# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  describe ".queue_options" do
    it "returns an empty hash by default" do
      expect(described_class.queue_options).to eq({})
    end
  end
end
