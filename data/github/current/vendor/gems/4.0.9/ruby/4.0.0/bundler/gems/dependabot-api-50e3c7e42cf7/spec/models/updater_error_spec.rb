# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdaterError, type: :model do
  describe "initialization" do
    it "accepts a Hash" do
      inputs = error_hash({})

      expect(described_class.new(inputs)).to be_a(described_class)
    end
  end

  describe "#updater_error?" do
    it "returns true" do
      inputs = error_hash({})

      expect(described_class.new(inputs).updater_error?).to be true
    end
  end

  describe "#original_error_class" do
    it "returns the class of the original error" do
      error_class = "RandomError"
      inputs = error_hash("error-class" => error_class)

      instance = described_class.new(inputs)

      expect(instance.original_error_class).to eq(error_class)
    end
  end

  describe "#message" do
    it "returns the message from the error hash" do
      message = "This is the error message"
      inputs = error_hash("error-message" => message)

      instance = described_class.new(inputs)

      expect(instance.message).to eq(message)
    end
  end

  describe "#rollup" do
    it "returns the same string when given the same inputs" do
      inputs = error_hash({
                            "error-class" => "MyErrorClass",
                            "error-backtrace" => caller.join("\n"),
                          })
      first = described_class.new(inputs)
      second = described_class.new(inputs)

      expect(first.rollup).to eq(second.rollup)
    end

    it "hashes the fingerprint value if provided" do
      inputs = error_hash({
                            "error-class" => "MyErrorClass",
                            "error-backtrace" => caller.join("\n"),
                          })

      without_fingerprint = described_class.new(inputs)
      with_fingerprint = described_class.new(inputs.merge("fingerprint" => "abc"))

      expect(with_fingerprint.rollup).not_to eq(without_fingerprint.rollup)
    end
  end

  describe "#backtrace" do
    it "returns the backtrace of the original error" do
      current_stacktrace = caller
      # we get a stacktrace as a string from the updater
      inputs = error_hash("error-backtrace" => current_stacktrace.join("\n"))

      instance = described_class.new(inputs)

      # We clean stacktraces to remove Dependabot's working directory, so we
      # ensure that each line of output is a subset of the input
      current_stacktrace.zip(instance.backtrace).each do |input, output|
        expect(input).to include(output)
      end
    end

    it "removes the job's working directory from the trace" do # rubocop:disable RSpec/ExampleLength
      original = <<~RAW
        /home/dependabot/common/lib/dependabot/shared_helpers.rb in run_helper_subprocess at line 189
        /home/dependabot/dependabot-updater/vendor/ruby/3.1.0/gems/sorbet-runtime-0.5.11193/lib/types/private/methods/call_validation.rb in bind_call at line 169
        /home/dependabot/dependabot-updater/vendor/ruby/3.1.0/gems/sorbet-runtime-0.5.11193/lib/types/private/methods/call_validation.rb in validate_call_skip_block_type at line 169
        /home/dependabot/dependabot-updater/vendor/ruby/3.1.0/gems/sorbet-runtime-0.5.11193/lib/types/private/methods/call_validation.rb in block in create_validator_slow_skip_block_type at line 111
        /home/dependabot/npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in run_yarn_top_level_updater at line 193
        /home/dependabot/npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in block (2 levels) in run_yarn_updater at line 116
        /home/dependabot/npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in chdir at line 109
        /home/dependabot/npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in block in run_yarn_updater at line 109
        /home/dependabot/common/lib/dependabot/shared_helpers.rb in with_git_configured at line 265
      RAW
      cleaned = <<~CLEANED
        common/lib/dependabot/shared_helpers.rb in run_helper_subprocess at line 189
        dependabot-updater/vendor/ruby/3.1.0/gems/sorbet-runtime-0.5.11193/lib/types/private/methods/call_validation.rb in bind_call at line 169
        dependabot-updater/vendor/ruby/3.1.0/gems/sorbet-runtime-0.5.11193/lib/types/private/methods/call_validation.rb in validate_call_skip_block_type at line 169
        dependabot-updater/vendor/ruby/3.1.0/gems/sorbet-runtime-0.5.11193/lib/types/private/methods/call_validation.rb in block in create_validator_slow_skip_block_type at line 111
        npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in run_yarn_top_level_updater at line 193
        npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in block (2 levels) in run_yarn_updater at line 116
        npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in chdir at line 109
        npm_and_yarn/lib/dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater.rb in block in run_yarn_updater at line 109
        common/lib/dependabot/shared_helpers.rb in with_git_configured at line 265
      CLEANED
      inputs = error_hash("error-backtrace" => original)

      instance = described_class.new(inputs)

      expect(instance.backtrace).to eq(cleaned.split("\n"))
    end
  end

  describe "#failbot_context" do
    it "returns a hash containing information for Failbot" do
      details = {
        "package-manager" => "FedEx",
        "job-dependencies" => ["citizenship", "green card"],
        "job-dependency-groups" => ["The Beatles"],
        "fingerprint" => "unique",
        "security-update" => true,
      }

      instance = described_class.new(error_hash(details))

      expect(instance.failbot_context).to include(details)
    end

    it "excludes nil values" do
      inputs = error_hash("package-manager" => nil)

      instance = described_class.new(inputs)

      expect(instance.failbot_context).not_to include("package-manager")
    end

    it "includes a rollup key/value pair" do
      instance = described_class.new(error_hash({}))

      expect(instance.failbot_context).to have_key("rollup")
    end

    it "includes a security-update key" do
      instance = described_class.new(error_hash({}))

      expect(instance.failbot_context).to have_key("security-update")
    end

    it "excludes 'security-update' when the value is missing" do
      inputs = error_hash("security-update" => nil)

      instance = described_class.new(inputs)
      expect(instance.failbot_context).not_to include("security-update")
    end

    it "includes a valid security-update value" do
      inputs = error_hash("security-update" => true)

      instance = described_class.new(inputs)
      expect(instance.failbot_context).to include("security-update")
    end
  end

  def error_hash(overrides)
    {
      "error-class" => "DefaultError",
      "error-message" => "This is the default message",
      "error-backtrace" => "default_frame1 default_frame2",
      "fingerprint" => nil,
      "package-manager" => "npm",
      "job-dependencies" => %w(dep1 dep2),
      "job-dependency-groups" => "group1",
      "security-update" => true,
    }.merge(overrides)
  end
end
