# frozen_string_literal: true

require "rails_helper"

RSpec.describe RefreshOpenGroupPullRequestsJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(update_config: update_config, manual: manual)
  end

  let(:account) do
    FactoryBot.create(
      :account,
      :active,
    )
  end

  let(:repo) do
    FactoryBot.create(
      :repo,
      account: account,
      config_file_path: ".github/dependabot.yml"
    )
  end

  let(:update_config) do
    FactoryBot.create(
      :update_config,
      :active,
      :daily,
      repo: repo
    )
  end

  let(:dependency_group) do
    FactoryBot.create(:dependency_group, update_config: update_config)
  end

  context "with default arguments" do
    let(:manual) { false }

    context "with no open pull requests" do
      it "doesn't enqueue any scheduled refresh jobs" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledRefreshJob)
      end
    end

    context "with an open non-group pull request" do
      before do
        FactoryBot.create(
          :pull_request,
          update_config: update_config
        )
      end

      it "doesn't enqueue any scheduled refresh jobs" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledRefreshJob)
      end
    end

    context "with an open group pull request" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      it "enqueues a scheduled refresh of the group PR" do
        expect { job.perform_now }.
          to have_enqueued_job(CreateScheduledRefreshJob).
          with(
            pull_request: pull_request,
            event_source: "job.refresh_open_group_pull_requests",
            manual: false
          )
      end

      context "when the dependency group has been deleted" do
        before do
          dependency_group.delete
        end

        it "doesn't enqueue any scheduled refresh jobs" do
          expect { job.perform_now }.
            not_to have_enqueued_job(CreateScheduledRefreshJob)
        end
      end
    end
  end

  context "when flagged as manually requested" do
    let(:manual) { true }

    context "with an open group pull request" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      it "enqueues a scheduled refresh of the group PR also flagged as manual" do
        expect { job.perform_now }.
          to have_enqueued_job(CreateScheduledRefreshJob).
          with(
            pull_request: pull_request,
            event_source: "job.refresh_open_group_pull_requests",
            manual: true
          )
      end
    end
  end
end
