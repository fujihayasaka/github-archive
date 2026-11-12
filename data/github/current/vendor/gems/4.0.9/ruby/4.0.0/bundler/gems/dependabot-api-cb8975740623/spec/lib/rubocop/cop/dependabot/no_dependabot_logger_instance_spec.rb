# frozen_string_literal: true

require "rails_helper"
require "rubocop"
require "rubocop/rspec/cop_helper"
require "rubocop/rspec/expect_offense"
require_relative "../../../../../lib/rubocop/cop/dependabot/no_dependabot_logger_instance"

RSpec.describe RuboCop::Cop::Dependabot::NoDependabotLoggerInstance do
  include CopHelper
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new }

  describe "#on_send" do
    context "when using Dependabot.logger" do
      it "registers an offense" do
        offenses = inspect_source("Dependabot.logger.info(msg: 'hello')")
        expect(offenses.size).to eq(1)
        expect(offenses.first.message).to include("Dependabot::Logger")
      end

      it "registers an offense for bare Dependabot.logger" do
        offenses = inspect_source("Dependabot.logger")
        expect(offenses.size).to eq(1)
      end
    end

    context "when using Dependabot::Logger" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          Dependabot::Logger.info(msg: "hello")
        RUBY
      end
    end

    context "when using Dependabot.logger=" do
      it "does not register an offense for assignment" do
        expect_no_offenses(<<~RUBY)
          Dependabot.logger = Rails.logger
        RUBY
      end
    end

    context "when using other Dependabot methods" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          Dependabot.flipper
        RUBY
      end
    end

    context "when autocorrecting" do
      it "replaces Dependabot.logger with Dependabot::Logger" do
        expect_offense(<<~RUBY)
          Dependabot.logger.info(msg: "hello")
          ^^^^^^^^^^^^^^^^^ Dependabot/NoDependabotLoggerInstance: Use `Dependabot::Logger` (structured Scrolls logger) instead of `Dependabot.logger` (dependabot-core Rails logger).
        RUBY

        expect_correction(<<~RUBY)
          Dependabot::Logger.info(msg: "hello")
        RUBY
      end
    end
  end
end
