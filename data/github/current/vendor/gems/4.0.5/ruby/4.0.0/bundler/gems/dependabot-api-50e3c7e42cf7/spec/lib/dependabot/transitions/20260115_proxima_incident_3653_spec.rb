# frozen_string_literal: true

require "rails_helper"
require "dependabot/transitions/20260115_proxima_incident_3653"

RSpec.describe Dependabot::Transitions::ProximaIncident3653, :proxima do
  let(:stamp_name) { "test-stamp-01" }
  let(:stamp_name_underscored) { "test_stamp_01" }
  let(:data_dir) { Rails.root.join("lib/dependabot/transitions/data").to_s }
  let(:data_file) { File.join(data_dir, "proxima_#{stamp_name_underscored}_repo_data.csv") }
  let(:options) { { dry_run: true, backfill_limit: 1000, verbose: false } }
  let(:transition) { described_class.new(**options) }

  before do
    FileUtils.mkdir_p(data_dir)
    allow(Prius).to receive(:get).and_call_original
    allow(Prius).to receive(:get).with(:proxima_stamp).and_return(stamp_name)
  end

  after do
    FileUtils.rm_f(data_file)
  end

  describe "#perform" do
    context "when PROXIMA_STAMP is not set" do
      before do
        allow(Prius).to receive(:get).and_call_original
        allow(Prius).to receive(:get).with(:proxima_stamp).and_return(nil)
      end

      it "raises an error" do
        expect { transition.run }.to raise_error(/PROXIMA_STAMP not set/)
      end
    end

    context "when data file is missing" do
      it "raises an error about missing data file" do
        expect { transition.run }.to raise_error(/Data file not found/)
      end
    end

    context "with valid data file" do
      let(:existing_repo) { create(:repo, github_id: 1001) }
      let(:csv_content) do
        <<~CSV
          repo_id,owner_id,tenant_id,tenant_slug
          #{existing_repo.github_id},#{existing_repo.account.github_id},tenant-123,test-tenant
          2002,3002,tenant-456,other-tenant
        CSV
      end

      before do
        existing_repo # ensure created
        File.write(data_file, csv_content)
      end

      it "syncs existing repos and identifies missing repos" do
        allow(SynchronizeRepoState).to receive(:new).
          with(repo: existing_repo, event_source: described_class::EVENT_SOURCE).
          and_return(instance_double(SynchronizeRepoState, run: true))

        allow(SetupAccountAndRepoWithGlobalAppJob).to receive(:perform_later).
          with(
            account_github_id: 3002,
            repo_github_id: 2002,
            tenant_id: "tenant-456",
            tenant_slug: "other-tenant",
            event_source: described_class::EVENT_SOURCE
          )

        options[:dry_run] = false
        transition.run

        expect(SynchronizeRepoState).to have_received(:new)
        expect(SetupAccountAndRepoWithGlobalAppJob).to have_received(:perform_later)
      end

      context "in dry-run mode" do
        it "does not sync or create repos" do
          expect(SynchronizeRepoState).not_to receive(:new)
          expect(SetupAccountAndRepoWithGlobalAppJob).not_to receive(:perform_later)
          transition.run
        end
      end

      context "with backfill_limit" do
        let(:options) { { dry_run: false, backfill_limit: 1, verbose: false } }

        it "respects the limit" do
          allow(SynchronizeRepoState).to receive(:new).
            and_return(instance_double(SynchronizeRepoState, run: true))

          transition.run

          expect(SynchronizeRepoState).to have_received(:new).once
        end
      end

      context "when sync raises an error" do
        before do
          allow(SynchronizeRepoState).to receive(:new).and_raise(StandardError.new("sync failed"))
        end

        it "logs the error and continues" do
          options[:dry_run] = false
          expect { transition.run }.not_to raise_error
        end
      end

      context "when job enqueue raises an error" do
        let(:csv_content) do
          <<~CSV
            repo_id,owner_id,tenant_id,tenant_slug
            2002,3002,tenant-456,other-tenant
          CSV
        end

        before do
          allow(SetupAccountAndRepoWithGlobalAppJob).to receive(:perform_later).
            and_raise(StandardError.new("enqueue failed"))
        end

        it "logs the error and continues" do
          options[:dry_run] = false
          expect { transition.run }.not_to raise_error
        end
      end
    end

    context "with repos missing tenant data" do
      let(:csv_content) do
        <<~CSV
          repo_id,owner_id,tenant_id,tenant_slug
          1001,2001,,
          1002,2002,tenant-123,
        CSV
      end

      before do
        File.write(data_file, csv_content)
      end

      it "skips repos with missing tenant info" do
        expect(SetupAccountAndRepoWithGlobalAppJob).not_to receive(:perform_later)
        transition.run
      end
    end
  end
end
