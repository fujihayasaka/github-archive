# frozen_string_literal: true

require "rails_helper"
require "rubocop"
require "rubocop/rspec/cop_helper"
require "rubocop/rspec/expect_offense"
require_relative "../../../../../lib/rubocop/cop/dependabot/no_local_feature_flags"

RSpec.describe RuboCop::Cop::Dependabot::NoLocalFeatureFlags do
  include CopHelper
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new }

  describe "#on_send" do
    context "when using config_feature_enabled?" do
      it "registers an offense for receiver.config_feature_enabled?" do
        offenses = inspect_source("repo.config_feature_enabled?(:my_feature)")
        expect(offenses.size).to eq(1)
        expect(offenses.first.message).to include("Local Flipper feature flags are deprecated")
      end

      it "registers an offense for self.config_feature_enabled?" do
        offenses = inspect_source("self.config_feature_enabled?(:my_feature)")
        expect(offenses.size).to eq(1)
      end

      it "registers an offense for config_feature_enabled? without receiver" do
        offenses = inspect_source("config_feature_enabled?(:my_feature)")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using org_level_flag_enabled?" do
      it "registers an offense" do
        offenses = inspect_source("repo.org_level_flag_enabled?(:my_feature)")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using repo_level_flag_enabled?" do
      it "registers an offense" do
        offenses = inspect_source("repo.repo_level_flag_enabled?(:my_feature)")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using enable_feature" do
      it "registers an offense" do
        offenses = inspect_source("repo.enable_feature(:my_feature)")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using disable_feature" do
      it "registers an offense" do
        offenses = inspect_source("repo.disable_feature(:my_feature)")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using Dependabot.flipper" do
      it "registers an offense for direct flipper access" do
        offenses = inspect_source("Dependabot.flipper[:my_feature].enable")
        expect(offenses.size).to eq(1)
        expect(offenses.first.message).to include("Dependabot.flipper")
      end

      it "registers an offense for flipper access with enable_actor" do
        offenses = inspect_source("Dependabot.flipper[:my_feature].enable_actor(self)")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using monolith_feature_enabled?" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          repo.monolith_feature_enabled?(:dependabot_my_feature)
        RUBY
      end

      it "does not register an offense for Application.monolith_feature_enabled?" do
        expect_no_offenses(<<~RUBY)
          Dependabot::Application.monolith_feature_enabled?(
            feature: :dependabot_my_feature,
            actor: repo
          )
        RUBY
      end
    end

    context "when using unrelated methods" do
      it "does not register an offense for other methods" do
        expect_no_offenses(<<~RUBY)
          repo.some_other_method(:foo)
        RUBY
      end

      it "does not register an offense for other flipper-like names" do
        expect_no_offenses(<<~RUBY)
          SomeOtherModule.flipper
        RUBY
      end
    end
  end
end
