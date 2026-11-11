# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::UpdateDependencyList do
  subject(:instance) { described_class.new(context) }

  let!(:update_job) { FactoryBot.create(:update_job, :processing) }
  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:dependency_files) { ["Gemfile", "Gemfile.lock"] }
  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: {
        dependencies: [
          { name: "useful_library", version: "1.2.0.4-rc3", requirements: [] },
          { name: "new_library", version: "3.beta1", requirements: [{ a: "b" }] },
        ],
        dependency_files: dependency_files,
      }
    )
  end

  context "for a processing update job" do
    it { is_expected.to respond_with_status(204) }

    it "doesn't create an update job" do
      expect { instance.call }.not_to change(UpdateJob, :count)
    end

    it "logs parameters" do
      allow(Dependabot::Logger).to receive(:info)
      instance.call

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               "code.namespace": "UpdateDependencyList",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
               dependency_count: 2,
               file_count: 2,
             ))
    end

    it "records job processing transition" do
      instance.call

      expect(MetricsClient).
        to have_received(:timing).with("update_job.update_dependency_list", kind_of(Float),
                                       tags: { package_manager: update_job.update_config.package_manager })
    end

    context "with dependency file details" do
      it "updates the monitored_files on the update config" do
        expect { instance.call }.
          to change { update_job.update_config.monitored_files }.
          from(nil).to(["Gemfile", "Gemfile.lock"])
      end
    end

    context "with too many dependency file details" do
      let(:dependency_files) { Array.new(60000) { |_i| "Gemfile" } }

      it "updates the monitored_files on the update config with a subset within the db limit" do
        expect { instance.call }.
          to change { update_job.update_config.monitored_files }.
          from(nil).to(Array.new(5416) { |_i| "Gemfile" })
      end
    end

    context "with invalid update config" do
      let!(:update_config) do
        FactoryBot.create(:update_config, :active,
                          repo: update_job.update_config.repo,
                          directory: "/other")
      end

      before do
        # Bypass validation on save
        update_config.update_attribute("directory", "/")
      end

      it { is_expected.to respond_with_status(204) }
    end
  end
end
