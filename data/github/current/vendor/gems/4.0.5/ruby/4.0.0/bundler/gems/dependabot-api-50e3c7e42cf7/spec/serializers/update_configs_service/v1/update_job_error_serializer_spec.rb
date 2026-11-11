# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::UpdateJobErrorSerializer,
               type: :serializer do
  let(:model_instance) do
    FactoryBot.create(:update_job_error)
  end

  let(:serialized_object) do
    described_class.new(model_instance)
  end

  describe "#git_dependencies_not_reachable_error" do
    subject { serialized_object.to_h[:git_dependencies_not_reachable_error] }

    context "by default" do
      it "is nil" do
        expect(subject).to be_nil
      end
    end

    context "for unreachable git dependency error" do
      let(:model_instance) do
        FactoryBot.create(:update_job_error,
                          error_type: "git_dependencies_not_reachable",
                          error_details: {
                            "dependency-urls" => [
                              "https://github.com/acme/alpha.git",
                              "https://github.com/acme/beta.git",
                            ],
                          },)
      end

      it "is present" do
        expect(subject).
          to eq({
                  urls: ["https://github.com/acme/alpha.git", "https://github.com/acme/beta.git"],
                })
      end
    end
  end
end
