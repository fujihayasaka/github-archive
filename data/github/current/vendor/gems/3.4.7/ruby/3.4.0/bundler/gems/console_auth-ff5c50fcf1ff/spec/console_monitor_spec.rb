# frozen_string_literal: true

require "stringio"
require "irb"
require "pry"


RSpec.describe ConsoleMonitor do
  let (:log_contents) { StringIO.new }
  let (:logger) { Logger.new(log_contents) }

  before do
    ConsoleMonitor.logger = logger
  end

  context "#install" do
    it "Logs a session started" do
      expect(logger).to receive(:info).with(hash_including(command: /session started at/)).and_call_original
      ConsoleMonitor.install
      log_contents.rewind
      expect(log_contents.read).to include("session started at")
    end

    it "logs what IRB context evaluates" do
      IRB.init_config(nil)
      IRB.conf[:USE_SINGLELINE] = false
      IRB.conf[:VERBOSE] = false
      workspace = IRB::WorkSpace.new(Object.new)
      @context = IRB::Context.new(nil, workspace)

      ConsoleMonitor.install

      expect(logger).to receive(:info).with(hash_including(command: "a = 42")).and_call_original
      @context.evaluate("a = 42", 1)
    end

    it "logs what Pry evals" do
      ConsoleMonitor.install
      pry = Pry.new(output: StringIO.new) # configure output to avoid printing to stdout

      expect(logger).to receive(:info).with(hash_including(command: "p = 42")).and_call_original
      pry.eval("p = 42")
    end
  end

  context "#log" do
    it "logs the session id" do
      allow(ConsoleAuth::Session).to receive(:session_id).and_return("abcdef")
      expect(logger).to receive(:info).with(hash_including(console_session: "abcdef")).and_call_original
      ConsoleMonitor.log("test log")
      log_contents.rewind
      expect(log_contents.read).to include(":console_session=>\"abcdef\"")
    end

    it "logs the irb console user" do
      allow(ConsoleAuth::Session).to receive(:console_user).and_return("monalia")
      expect(logger).to receive(:info).with(hash_including(console_user: "monalia")).and_call_original
      ConsoleMonitor.log("test log")
      log_contents.rewind
      expect(log_contents.read).to include(":console_user=>\"monalia\"")
    end

    it "logs the shell user" do
      allow(ConsoleMonitor).to receive(:shell_user).and_return("monashell")
      expect(logger).to receive(:info).with(hash_including(shell_user: "monashell")).and_call_original
      ConsoleMonitor.log("test log")
      log_contents.rewind
      expect(log_contents.read).to include(":shell_user=>\"monashell\"")
    end

    it "logs a splunk index for routing" do
      expect(logger).to receive(:info).with(hash_including(splunk_index: "sec-prod-console")).and_call_original
      ConsoleMonitor.log("test log")
      log_contents.rewind
      expect(log_contents.read).to include(":splunk_index=>\"sec-prod-console\"")
    end
  end
end
