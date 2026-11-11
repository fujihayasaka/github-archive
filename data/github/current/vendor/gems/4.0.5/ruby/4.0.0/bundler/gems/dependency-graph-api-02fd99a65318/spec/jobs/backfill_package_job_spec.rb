require "rails_helper"

describe BackfillPackageJob do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  describe "#perform" do
    it "calls OneOffImporters to backfill missing versions" do
      allow(OneOffImporters).to receive(:run!)
      expect(OneOffImporters).to receive(:run!).with(:npm, package_name: "express")

      BackfillPackageJob.new.perform(:npm, "express")
    end

    it "only calls OneOffImporters once when processing same package multiple times" do
      allow(OneOffImporters).to receive(:run!)
      expect(OneOffImporters).to receive(:run!).with(:npm, package_name: "express").once

      BackfillPackageJob.new.perform(:npm, "express")
      BackfillPackageJob.new.perform(:npm, "express")
      BackfillPackageJob.new.perform(:npm, "express")
    end

    it "handles special characters in package names" do
      allow(OneOffImporters).to receive(:run!)
      expect(OneOffImporters).to receive(:run!).with(:npm, package_name: "@babel/core")

      BackfillPackageJob.new.perform(:npm, "@babel/core")
    end

    it "works with different package managers" do
      allow(OneOffImporters).to receive(:run!)
      expect(OneOffImporters).to receive(:run!).with(:rubygems, package_name: "rails")

      BackfillPackageJob.new.perform(:rubygems, "rails")
    end

    context "when OneOffImporters raises an error" do
      before do
        allow(OneOffImporters).to receive(:run!).and_raise(StandardError.new("registry timeout"))
        allow(Rails.logger).to receive(:error)
        allow(Failbot).to receive(:report)
      end

      it "does not break the job" do
        expect { BackfillPackageJob.new.perform(:npm, "express") }.not_to raise_error
      end

      it "logs the error with context" do
        BackfillPackageJob.new.perform(:npm, "express")

        expect(Rails.logger).to have_received(:error).with("Failed to backfill npm package express: registry timeout")
      end

      it "reports the error to Failbot with metadata" do
        job = BackfillPackageJob.new
        job.perform(:npm, "express")

        expect(Failbot).to have_received(:report).with(
          instance_of(StandardError),
          "gh.aqueduct.queue.name" => job.queue_name,
          "gh.aqueduct.job.name" => "backfill_package_job"
        )
      end

      it "allows retry on subsequent call" do
        BackfillPackageJob.new.perform(:npm, "express")

        allow(OneOffImporters).to receive(:run!)
        expect(OneOffImporters).to receive(:run!).with(:npm, package_name: "express")

        BackfillPackageJob.new.perform(:npm, "express")
      end
    end
  end
end
