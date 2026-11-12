# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutofixSuggestionJob::Stages do
  let(:stage) { :stage }

  describe ".record_success" do
    it "records a stage success" do
      expect(MetricsClient).to receive(:increment).with(
        "autofix_job.stage_result",
        tags: { stage: stage.to_s, result: "success" }
      )
      expect(Dependabot::Logger).to receive(:info).with(
        hash_including(msg: "Autofix job stage result", "prop.id": "id")
      )

      described_class.record_success(stage: stage, "prop.id": "id")
    end
  end

  describe ".record_error" do
    it "records a stage error" do
      expect(MetricsClient).to receive(:increment).with(
        "autofix_job.stage_result",
        tags: { stage: stage.to_s, result: "error" }
      )
      expect(Dependabot::Logger).to receive(:error).with(
        hash_including(
          msg: "Autofix job stage result",
          "exception.type": "RuntimeError",
          "exception.message": "test",
          "prop.id": "id",
        )
      )

      described_class.record_error(stage: stage, error: RuntimeError.new("test"), "prop.id": "id")
    end
  end
end
