require "rails_helper"
require_relative "../../../lib/monolith/features"

describe Monolith::Features do
  let(:features) { described_class.new }
  let(:flag) { "a_flag" }
  let(:repo) { Repository.create!(github_repository_id: 4,
                                  github_owner_id: 2,
                                  nwo: "monalisa/smile",
                                  public: true)
  }
  let(:other_repo) { Repository.create!(github_repository_id: 10,
                                      github_owner_id: 2,
                                      nwo: "monalisa/frown")
  }

  before do
    VCR.insert_cassette("features", allow_playback_repeats: true, match_requests_on: [:body, :uri])
  end

  after do
    VCR.eject_cassette
  end

  context "feature_enabled?" do
    it "successfully returns booleans" do
      # flag is enabled for monalisa (user 2) and monalisa/smile (repo 4)
      expect(features.feature_enabled?(feature: flag)).to be_falsey
      expect(features.feature_enabled?(feature: flag, actor_id: "User:2")).to be_truthy
      expect(features.feature_enabled?(feature: flag, actor_id: "Repository:4")).to be_truthy
      expect(features.feature_enabled?(feature: flag, actor_id: "User:3")).to be_falsey
    end

    it "successfully returns fallback when Faraday timeout occurs" do
      fallback = true

      allow_any_instance_of(Monolith::TwirpClient).to receive(:connection).and_raise(Faraday::TimeoutError.new)
      expect(features.feature_enabled?(feature: flag, actor_id: "User:3", fallback: fallback)).to eq(fallback)
    end

    it "successfully returns fallback when twirp features url is not set eg in enterprise" do
      fallback = true

      allow(Rails.application).to receive(:config_for).and_return({})
      fallback_client = described_class.new

      expect(features.feature_enabled?(feature: flag, actor_id: "User:3", fallback: fallback)).to eq(fallback)
    end
  end

  context "multi-actor checks" do
    it "all_actors_feature returns true if all supplied actors are enabled" do
      # flag is enabled for monalisa (user 2) only
      res = features.all_actors_feature(actor_ids: ["User:2", "User:3"], feature: flag)
      expect(res).to be_falsey
    end

    it "any_actors_feature returns true if any supplied actors are enabled" do
      # flag is enabled for monalisa (user 2) only
      res = features.any_actors_feature(actor_ids: ["User:2", "User:3"], feature: flag)
      expect(res).to be_truthy
    end

    it "check_actors_feature returns a hash of actor IDs to results" do
      # flag is enabled for monalisa (user 2) only
      res = features.check_actors_feature(actor_ids: ["User:2", "User:3"], feature: flag)

      expect(res.count).to eq(2)
      expect(res.first.class).to eq(MonolithTwirp::Features::Core::V1::ActorFeatureResult)

      results = {}
      res.each do |feature|
        results[feature.actor_id] = feature.is_enabled
      end

      expect(results["User:2"]).to be_truthy
      expect(results["User:3"]).to be_falsey
    end

    it "check_actors_feature returns a hash of actor IDs to false results as fallback" do
      input_actors = ["User:99", "Repository:44"]

      allow(Rails.application).to receive(:config_for).and_return({})
      fallback_client = described_class.new

      # call features wrapper (same method name as client!) with some actors
      res = fallback_client.check_actors_feature(actor_ids: input_actors, feature: flag)

      # expect array of 2 actor feature results, all disabled, as fallback
      expect(res.count).to eq(2)
      expect(res.first.class).to eq(MonolithTwirp::Features::Core::V1::ActorFeatureResult)
      res.each do |feature|
        expect(feature.is_enabled).to be_falsey
      end
    end
  end

  context "feature_enabled_for_repo" do
    it "correctly checks if repo actor is enabled given repo object" do
      # flag is enabled for monalisa/smile only
      expect(features.feature_enabled_for_repo?(github_repository_id: repo.github_repository_id, feature: flag)).to be_truthy
      expect(features.feature_enabled_for_repo?(github_repository_id: other_repo.github_repository_id, feature: flag)).to be_falsey
    end

    it "correctly checks if repo owner is enabled given repo object" do
      disabled_owner_repo = Repository.create!(github_repository_id: 20, github_owner_id: 5, nwo: "faux_monalisa/smile")

      # flag is enabled for monalisa only
      expect(features.feature_enabled_for_repo_owner?(github_owner_id: repo.github_owner_id, feature: flag)).to be_truthy
      expect(features.feature_enabled_for_repo_owner?(github_owner_id: other_repo.github_owner_id, feature: flag)).to be_truthy
      expect(features.feature_enabled_for_repo_owner?(github_owner_id: disabled_owner_repo.github_owner_id, feature: flag)).to be_falsey
    end
  end
end
