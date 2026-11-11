# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigResolver do
  subject(:resolver) do
    described_class.for(repo)
  end

  let(:repo) { FactoryBot.create(:repo) }
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:directory) { "/." }
  let(:directories) { nil }
  let(:package_manager) { "bundler" }
  let(:target_branch) { nil }
  let(:update_schedule) { "never" }

  let(:existing_update_config) do
    FactoryBot.create(
      :update_config, :active,
      repo: repo,
      target_branch: target_branch,
      directory: directory,
      directories: directories,
      package_manager: package_manager,
      update_schedule: update_schedule
    )
  end

  it "returns the first update config in the repo" do
    expect(existing_update_config).to eq(resolver.first)
  end

  it "raises an error when package manager is nil" do
    expect { resolver.with_package_manager(nil) }.to raise_error(ArgumentError)
  end

  it "raises an error when directory is nil" do
    expect { resolver.with_directory(nil) }.to raise_error(ArgumentError)
  end

  context "searching for user-defined update configs" do
    let(:update_schedule) { "daily" }

    it "returns the update config that is user-defined" do
      expect(existing_update_config).to eq(resolver.user_defined.first)
    end
  end

  context "searching for ephemeral update configs" do
    it "returns the update config that is ephemeral" do
      expect(existing_update_config).to eq(resolver.ephemeral.first)
    end
  end

  context "searching by package manager" do
    it "returns the matching update config" do
      expect(existing_update_config).to eq(resolver.with_package_manager("bundler").first)
    end

    it "returns nil when nothing matches" do
      expect(existing_update_config).not_to eq(resolver.with_package_manager("cargo").first)
      expect(resolver.with_package_manager("cargo").first).to be_nil
    end
  end

  context "searching by target branch" do
    it "returns the matching update config" do
      expect(existing_update_config).to eq(resolver.with_target_branch(nil).first)
    end

    it "returns nil when nothing matches" do
      expect(existing_update_config).not_to eq(resolver.with_target_branch("dev").first)
      expect(resolver.with_target_branch("dev").first).to be_nil
    end
  end

  context "for an update config with directory" do
    let(:directory) { "/." }

    it "returns the existing update config with a match" do
      expect(existing_update_config).to eq(resolver.with_directory("/.").first)
    end
  end

  context "for an update config with a glob in directory column" do
    let(:directory) { "/foo/*" }

    it "returns the existing update config with a match" do
      expect(existing_update_config).to eq(resolver.with_directory("/foo/bar").first)
    end
  end

  context "for an update config with directories" do
    let(:directory) { nil }
    let(:directories) { ["/bar", "/foo"] }

    it "returns the existing update config with an exact match" do
      expect(existing_update_config).to eq(resolver.first)
    end

    context "searching for a subset of the directories" do
      it "finds the update config that contains the directory" do
        expect(existing_update_config).to eq(resolver.with_directory("/foo").first)
      end
    end
  end

  context "for an update config that uses a glob that matches everything" do
    let(:directory) { nil }
    let(:directories) { ["**/*"] }

    it "finds the glob update config with any directory" do
      expect(existing_update_config).to eq(resolver.with_directory("/.").first)
      expect(existing_update_config).to eq(resolver.with_directory("/foo").first)
      expect(existing_update_config).to eq(resolver.with_directory("/foo/bar").first)
      expect(existing_update_config).to eq(resolver.with_directory("/.foo/.bar/.baz").first)
    end
  end
end
