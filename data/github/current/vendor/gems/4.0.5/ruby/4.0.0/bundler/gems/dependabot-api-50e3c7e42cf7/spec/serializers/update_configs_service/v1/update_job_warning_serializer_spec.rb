# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::UpdateJobWarningSerializer, type: :serializer do
  let(:model_instance) do
    FactoryBot.create(:update_job_warning)
  end

  let(:serialized_object) do
    described_class.new(model_instance)
  end

  describe "#type" do
    subject(:type) { serialized_object.to_h[:type] }

    context "with default values" do
      it "returns the warning type" do
        expect(type).to eq(model_instance.warn_type)
      end
    end
  end

  describe "#title" do
    subject(:title) { serialized_object.to_h[:title] }

    context "with a title set" do
      let(:model_instance) do
        FactoryBot.create(:update_job_warning, warn_title: "My Warning Title")
      end

      it "returns the warning title" do
        expect(title).to eq("My Warning Title")
      end
    end
  end

  describe "#description" do
    subject(:description) { serialized_object.to_h[:description] }

    context "with a description set" do
      let(:model_instance) do
        FactoryBot.create(:update_job_warning, warn_description: "My Warning Description")
      end

      it "returns the warning description" do
        expect(description).to eq("My Warning Description")
      end
    end

    context "with no description set" do
      before do
        model_instance.update_columns(warn_description: nil) # Bypass validation
      end

      it "returns the default warning description" do
        expect(description).to eq(UpdateJobWarningPresenter::DEFAULT_WARNING_DESCRIPTION)
      end
    end
  end
end
