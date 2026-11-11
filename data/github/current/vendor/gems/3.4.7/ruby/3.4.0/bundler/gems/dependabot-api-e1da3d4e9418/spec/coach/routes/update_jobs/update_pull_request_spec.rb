# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::UpdatePullRequest do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) { params_hash.deep_symbolize_keys }
  let(:params_hash) do
    {
      data: {
        "dependency-names" => [name],
        "updated-dependency-files" => files,
        "base-commit-sha" => "sha",
      },
    }
  end
  let(:name) { "business" }
  let(:files) do
    [
      {
        content: "some things",
        name: "Gemfile",
        directory: "/",
        type: "file",
        support_file: false,
        content_encoding: "utf-8",
        deleted: false,
        operation: "update",
      },
      {
        content: "more things",
        name: "Gemfile.lock",
        directory: "/",
        type: "file",
        support_file: false,
        content_encoding: "utf-8",
        deleted: false,
        operation: "update",
      },
    ]
  end

  context "for an enqueued update job" do
    let(:update_job) { FactoryBot.create(:update_job, :enqueued) }

    it { is_expected.to respond_with_status(400) }
  end

  context "for an update job targetting a specific dependency" do
    let(:update_config) { FactoryBot.create(:update_config) }

    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :updating,
        update_job: old_update_job,
        dependencies: [
          {
            name: "business",
            version: "1.8.0",
          },
        ],
      )
    end

    let(:update_job) do
      update_job = pull_request.last_transition.update_job
      update_job.transition_to!(:enqueued)
      update_job.transition_to!(:processing)
      update_job
    end
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :updating,
        update_job: old_update_job,
        dependencies: [
          {
            name: "business",
            version: "1.8.0",
          },
        ],
      )
    end
    let(:old_update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end

    context "that isn't the dependency that has been updated" do
      let(:name) { "prius" }

      it { is_expected.to respond_with_status(400) }
    end

    it { is_expected.to respond_with_status(204) }

    it "enqueues a job to update the PR" do
      expect { instance.call }.to(
        have_enqueued_job(UpdatePullRequestJob).with do |args|
          update_job_id = args.fetch(:update_job_id)
          expect(update_job_id).to eql(update_job.id)

          pending_pr_update = args.fetch(:pending_pull_request_update)
          expect(pending_pr_update).to be_persisted

          expect(pending_pr_update.updated_dependency_files.map(&:to_h)).
            to eq(files.map(&:stringify_keys))
        end
      )
    end

    it "increments the update as initialized" do
      expect(MetricsClient).
        to receive(:count).
        with("update_pull_request.initiated", 1, tags: hash_including(
          grouped_update: false
        ))

      instance.call
    end

    context "for a grouped update PR" do
      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          :updating,
          update_job: old_update_job,
          dependencies: [
            {
              name: "business",
              version: "1.8.0",
            },
          ],
          grouped_update: true,
          dependency_group: FactoryBot.create(:dependency_group)
        )
      end

      it "increments the update as initialized" do
        expect(MetricsClient).
          to receive(:count).
          with("update_pull_request.initiated", 1, tags: hash_including(
            grouped_update: true
          ))

        instance.call
      end
    end
  end
end
