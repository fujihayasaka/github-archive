# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::ApplicationScheduledJob, type: :job do
  before do
    dummy_class = Class.new(described_class) do
      def perform
        raise unless ::Dependabot::Exceptions.context.any? { |c| c[:transaction] == "DummyJob" }
      end
    end
    stub_const("DummyJob", dummy_class)
  end

  describe "#perform" do
    it "sets up the exception context" do
      ::Dependabot::Exceptions.reset!
      ::Dependabot::Exceptions.push({ "gh.repo.id": 123 })

      DummyJob.new.perform_now
      expect(::Dependabot::Exceptions.context.none? { |c| c.key?(:transaction) }).to be true
    end
  end
end
