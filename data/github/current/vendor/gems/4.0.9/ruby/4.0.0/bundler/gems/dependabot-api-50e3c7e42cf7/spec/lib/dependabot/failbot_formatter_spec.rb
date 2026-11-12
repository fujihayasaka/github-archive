# frozen_string_literal: true

require "spec_helper"
require "dependabot/failbot_formatter"
require "failbot/rails"

class TestFailbotFormatterError < StandardError; end

RSpec.describe Dependabot::FailbotFormatter do
  before do
    Failbot.reset!
    Failbot::Config::EXCEPTION_FORMATS[:structured_scrubbed] = described_class
    ENV["FAILBOT_RAISE"] = ""
    ENV["FAILBOT_EXCEPTION_FORMAT"] = "structured_scrubbed"
    Failbot::Rails.setup("dependabot-api")
  end

  after do
    ENV.delete("FAILBOT_RAISE")
    ENV.delete("FAILBOT_EXCEPTION_FORMAT")
  end

  let(:wrapper_class) do
    Class.new(StandardError) do
      def original_error_class
        "OriginalError"
      end
    end
  end

  it "scrubs sensitive repo NWO data from an api url" do
    error = StandardError.new("POST https://api.github.com/repos/foo/bar/issues/2/assignees: 422")
    expected_message = "POST https://api.github.com/repos/foo/[FILTERED_REPO]/issues/2/assignees: 422"

    Failbot.report(error)
    expect(last_failbot_message).to eq(expected_message)
  end

  it "filters sensitive data from a nested cause" do
    nested_error = begin
      raise TestFailbotFormatterError, "POST https://github.com/foo/bar: 404"
    rescue TestFailbotFormatterError
      begin
        raise StandardError, "POST https://github.com/foo/bar: 404"
      rescue StandardError => e
        e
      end
    end
    expected_message = "POST https://github.com/foo/[FILTERED_REPO]: 404"

    Failbot.report(nested_error)

    expect(total_failbot_messages).to be(2)

    each_failbot_message do |message|
      expect(message).to eq(expected_message)
    end
  end

  it "reports the original_error_class when possible" do
    wrapped_error = wrapper_class.new("WrappedError")

    Failbot.report(wrapped_error)

    expect(last_error_type).to eq(wrapped_error.original_error_class)
  end

  it "reports an error's class name when no original_error_class is present" do
    error = StandardError.new

    Failbot.report(error)

    expect(last_error_type).to eq(error.class.to_s)
  end

  private

  def total_failbot_messages
    Failbot.reports.last["exception_detail"].count
  end

  def last_failbot_message
    Failbot.reports.last["exception_detail"].last["value"]
  end

  def last_error_type
    Failbot.reports.last["exception_detail"].last["type"]
  end

  def each_failbot_message
    Failbot.reports.last["exception_detail"].each do |detail|
      yield(detail["value"])
    end
  end
end
