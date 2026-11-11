# frozen_string_literal: true
require "rails_helper"

describe DependencyGraph::FailbotLogger do
  describe "log_exception method" do
    it "reorders failbot fields" do
      failbot_logger = DependencyGraph::FailbotLogger.new
      e = RuntimeError.new("BOOM")
      e.set_backtrace caller
      data = { "foo" => "bar", "app" => "github", "failbot_dg_id" => "test" }

      expect(DependencyGraph.logger).to receive(:info) do |data, exception|
        data.keys == ["failbot_dg_id", "failbot_app", "exception_type", "exception_value", "foo"]
      end

      failbot_logger.log_exception(data, e)
    end

    it "drops stacktrace field" do
      failbot_logger = DependencyGraph::FailbotLogger.new
      e = RuntimeError.new("BOOM")
      e.set_backtrace caller
      data = { "foo" => "bar" }

      expect(DependencyGraph.logger).to receive(:info) do |data, exception|
        !data.has_key?("exception_detail") &&
        data["exception_type"] == "RuntimeError" &&
        data["exception_value"] == "BOOM" &&
        data["foo"] == "bar"
      end

      failbot_logger.log_exception(data, e)
    end

    it "renames app key to failbot_app" do
      failbot_logger = DependencyGraph::FailbotLogger.new
      e = RuntimeError.new("BOOM")
      e.set_backtrace caller
      data = { "foo" => "bar", "app" => "github" }

      expect(DependencyGraph.logger).to receive(:info) do |data, exception|
        !data.has_key?("app") && data["failbot_app"] == "github"
      end

      failbot_logger.log_exception(data, e)
    end

    it "escapes newlines in backtrace so it comes out as a single line" do
      failbot_logger = DependencyGraph::FailbotLogger.new
      e = RuntimeError.new("BOOM")
      e.set_backtrace caller
      data = { "foo" => "bar\nbaz" }

      expect(DependencyGraph.logger).to receive(:info) do |data, exception|
        data["foo"] == "bar\\nbaz"
      end

      failbot_logger.log_exception(data, e)
    end
  end

  it "escapes newlines in additional data so it comes out as a single line" do
    failbot_logger = DependencyGraph::FailbotLogger.new
    e = RuntimeError.new("This is a \n message with \n newlines")
    e.set_backtrace caller
    data = Failbot.exception_info(e).merge({ "key" => "wow\ncrazy!" })

    expect(DependencyGraph.logger).to receive(:info).with hash_including(
      "exception_type" => "RuntimeError",
      "exception_value" => "This is a \\n message with \\n newlines",
      "key" => "wow\\ncrazy!"
    )

    failbot_logger.log_exception(data, e)
  end

  it "logs causes" do
    failbot_logger = DependencyGraph::FailbotLogger.new
    wrapped_exception = begin
                          begin
                            begin
                              raise Zlib::Error, "failed to zip private private private"
                            rescue
                              raise Trilogy::MysqlError, "PII all over the place"
                            end
                          rescue
                            raise "outer exception, no PII here!"
                          end
                        rescue => e
                          e
                        end
    expect(DependencyGraph.logger).to receive(:info) do |data, exception|
      data == {
        "exception_type" => "RuntimeError",
        "exception_value" => "outer exception, no PII here!",
        "causes" => [
          { "type" => "Zlib::Error",         "value" => "failed to zip private private private" },
          { "type" => "Trilogy::MysqlError", "value" => "PII all over the place" }
        ]
      }
    end
    failbot_logger.log_exception({}, e)
  end
end
