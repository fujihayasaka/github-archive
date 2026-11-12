# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepoSerializer, type: :serializer do
  subject(:serialized_repo) { described_class.new(repo) }

  describe "#installation_state" do
    subject { serialized_repo.installation_state }

    context "with an unpersisted repo" do
      let(:repo) { Repo.new }

      it { is_expected.to eq("inactive") }
    end

    context "with an active repo" do
      let(:repo) { FactoryBot.create(:repo, :active) }

      it { is_expected.to eq("active") }
    end

    context "with an inactive repo" do
      let(:repo) { FactoryBot.create(:repo, :inactive) }

      it { is_expected.to eq("inactive") }
    end
  end

  describe "#id" do
    subject { serialized_repo.id }

    context "with an unpersisted repo" do
      let(:repo) { Repo.new(github_id: 12) }

      it { is_expected.to eq(12) }
    end

    context "with a persisted repo" do
      let(:repo) { FactoryBot.create(:repo, id: 3, github_id: 12) }

      it { is_expected.to eq(12) }
    end
  end
end
