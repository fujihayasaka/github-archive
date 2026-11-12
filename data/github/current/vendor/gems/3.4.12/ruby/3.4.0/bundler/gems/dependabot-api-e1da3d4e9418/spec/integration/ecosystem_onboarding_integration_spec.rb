# frozen_string_literal: true

require "rails_helper"
require "ecosystem_onboarding"
require "fileutils"
require "tmpdir"

RSpec.describe "Ecosystem Onboarding Integration", type: :integration do
  include OutputHelpers

  describe "full onboarding workflow" do
    it "reports the correct ecosystem and package manager names" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "my_ecosystem",
        package_manager_name: "my_pm",
        mode: "skip"
      )

      output = capture_output { onboarding.run }

      expect(output).to include("Ecosystem: my_ecosystem")
      expect(output).to include("Package Manager: my_pm")
    end

    it "works with ecosystem name only (defaulting package manager)" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "solo_eco",
        mode: "skip"
      )

      expect(onboarding.package_manager_name).to eq("solo_eco")

      output = capture_output { onboarding.run }

      expect(output).to include("Ecosystem: solo_eco")
      expect(output).to include("Package Manager: solo_eco")
    end
  end

  describe "file modifications" do
    around do |example|
      # Backup original files
      proto_file = Rails.root.join("proto/dependabot-api/twirp/dependabot_api.proto")
      ecosystems_file = Rails.root.join("lib/ecosystems.rb")
      regex_file = Rails.root.join("lib/ecosystem_file_regex.rb")
      parse_config_file = Rails.root.join("app/actions/parse_config_file.rb")
      schema_file = Rails.root.join("config/config_file_json_schema.json")

      original_proto = File.read(proto_file)
      original_ecosystems = File.read(ecosystems_file)
      original_regex = File.read(regex_file)
      original_parse_config = File.read(parse_config_file)
      original_schema = File.read(schema_file)

      begin
        example.run
      ensure
        # Restore original files
        File.write(proto_file, original_proto)
        File.write(ecosystems_file, original_ecosystems)
        File.write(regex_file, original_regex)
        File.write(parse_config_file, original_parse_config)
        File.write(schema_file, original_schema)
      end
    end

    it "successfully onboards a new ecosystem in overwrite mode" do
      # Use a unique name to avoid conflicts with previous test runs
      unique_suffix = Time.now.to_i.to_s[-6..]
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "test_eco_#{unique_suffix}",
        package_manager_name: "test_pm_#{unique_suffix}",
        mode: "overwrite"
      )

      output = capture_output { onboarding.run }

      # Verify summary output includes expected sections
      expect(output).to include("=== Ecosystem Onboarding Tool ===")
      expect(output).to include("SUMMARY")
      expect(output).to include("Onboarding complete!")

      # Verify changes were tracked
      expect(onboarding.changes_made).not_to be_empty

      # Verify manual steps were tracked
      expect(onboarding.manual_steps).not_to be_empty
      expect(onboarding.manual_steps).to include(match(/protoc/))
    end

    it "modifies protobuf file correctly" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "proto_test_eco",
        package_manager_name: "proto_test_pm",
        mode: "overwrite"
      )

      # Suppress output
      suppress_output { onboarding.run }

      proto_content = Rails.root.join("proto/dependabot-api/twirp/dependabot_api.proto").read
      expect(proto_content).to include("PROTO_TEST_ECO")
    end

    it "modifies ecosystems.rb correctly" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "eco_test",
        package_manager_name: "eco_test_pm",
        mode: "overwrite"
      )

      suppress_output { onboarding.run }

      ecosystems_content = Rails.root.join("lib/ecosystems.rb").read
      expect(ecosystems_content).to include("ECO_TEST_PM = \"eco_test_pm\"")
      expect(ecosystems_content).to include("PackageManagers::ECO_TEST_PM => nil, # TODO: map to a new or " \
                                            "existing language from `Languages`")
    end

    it "modifies ecosystem_file_regex.rb correctly" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "regex_test",
        package_manager_name: "regex_test_pm",
        mode: "overwrite"
      )

      suppress_output { onboarding.run }

      regex_content = Rails.root.join("lib/ecosystem_file_regex.rb").read
      expect(regex_content).to include("def regex_test_pm_regex")
      expect(regex_content).to include("# TODO: Add the correct file patterns")
    end

    it "modifies parse_config_file.rb correctly" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "parse_test",
        package_manager_name: "parse_test_pm",
        mode: "overwrite"
      )

      suppress_output { onboarding.run }

      parse_content = Rails.root.join("app/actions/parse_config_file.rb").read
      expect(parse_content).to include("\"parse_test\" => PackageManagers::PARSE_TEST_PM")
    end

    it "modifies config JSON schema correctly" do
      onboarding = EcosystemOnboarding.new(
        ecosystem_name: "schema_test",
        package_manager_name: "schema_test_pm",
        mode: "overwrite"
      )

      suppress_output { onboarding.run }

      schema_content = Rails.root.join("config/config_file_json_schema.json").read
      schema = JSON.parse(schema_content)

      expect(schema.dig("definitions", "package-ecosystem", "enum")).to include("schema_test")
      expect(schema["definitions"]).to have_key("schema_test")
    end
  end
end
