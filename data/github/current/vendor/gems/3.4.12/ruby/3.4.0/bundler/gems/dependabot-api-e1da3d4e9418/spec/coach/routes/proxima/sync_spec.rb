# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::Proxima::Sync do
  include ProximaHelpers

  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request } }
  let(:request) { instance_double(ActionDispatch::Request) }

  before do
    create(:updater_version,
           ecosystem: "bundler",
           version: "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98",
           env: UpdaterVersion.envs[:prod])
    create(:updater_version,
           ecosystem: "npm",
           version: "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98",
           env: UpdaterVersion.envs[:prod])
    create(:updater_version,
           ecosystem: "gomod",
           version: "800437640d2ff4f6380ef21b90f685be7ac140e6",
           env: UpdaterVersion.envs[:prod])
    create(:updater_version,
           ecosystem: "gomod",
           version: "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98",
           env: UpdaterVersion.envs[:stage])
  end

  context "in the cloud/dotcom", :cloud do
    it { is_expected.to respond_with_status(200) }

    it "returns the ecosystem versions currently configured" do
      response = instance.call

      expect(JSON.parse(response[2].first)).to eq({
                                                    "ecosystem_versions" => [
                                                      { "ecosystem" => "npm",
                                                        "version" => "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98", },
                                                      { "ecosystem" => "gomod",
                                                        "version" => "800437640d2ff4f6380ef21b90f685be7ac140e6", },
                                                      { "ecosystem" => "bundler",
                                                        "version" => "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98", },
                                                    ],
                                                  })
    end
  end

  context "in proxima", :proxima do
    it { is_expected.to respond_with_status(404) }
    it { is_expected.to respond_with_body_that_matches(/Not found/) }
  end

  context "in GHES", :enterprise do
    it { is_expected.to respond_with_status(404) }
    it { is_expected.to respond_with_body_that_matches(/Not found/) }
  end
end
