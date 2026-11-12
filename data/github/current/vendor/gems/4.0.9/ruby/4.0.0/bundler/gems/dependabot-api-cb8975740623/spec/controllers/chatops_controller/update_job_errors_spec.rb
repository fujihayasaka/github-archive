# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers
  include GitHubSecurityAdvisoryHelpers

  include_context "chatops controller"

  describe "update_job_errors" do
    it "says there are no errors and suggests --private" do
      chat "dependabot update-job-errors --error-type update_not_possible",
           "user", "#dependabot-ops"

      expect(chatop_response).
        to include("No update job errors were found")
      expect(chatop_response).
        to include("Try using `--private` to search private repos instead")
    end

    it "says there are no errors without suggesting --private when already using it" do
      chat "dependabot update-job-errors --error-type update_not_possible --private true",
           "user", "#dependabot-ops"

      expect(chatop_response).
        to include("No update job errors were found")
      expect(chatop_response).
        not_to include("--private")
    end

    context "with update job errors" do
      let!(:private_update_job_error) do
        FactoryBot.create(:update_job_error, error_type: "update_not_possible")
      end

      let!(:update_job_error) do
        build_error("bundler", "rails", "update_not_possible")
      end

      before do
        build_error("bundler", "rack", "unkown_error")
        build_error("npm_and_yarn", "node-forge", "update_not_possible")
      end

      it "prints dry-run commands for recent update_not_possible errors" do
        mock_github_security_advisory_fetch(dependency_name: "rails", package_manager: "bundler")

        chat "dependabot update-job-errors --package-manager bundler "\
             "--error-type update_not_possible",
             "user", "#dependabot-ops"

        expect(chatop_response).
          to include(".dependabot job #{update_job_error.update_job_id}")
        expect(chatop_response).
          to include("SECURITY_ADVISORIES='"\
                     "[{\"dependency-name\":\"rails\"")
        expect(chatop_response).
          to include("bin/dry-run.rb bundler \"hmarr/business\" --dir=\"/\" "\
                     "--dep=\"rails\" --security-updates-only")
        expect(chatop_response).not_to include("bin/dry-run.rb npm_and_yarn")
        expect(chatop_response).not_to include("--dep=\"rack\"")
      end

      it "does not include private repo errors by default" do
        chat "dependabot update-job-errors --error-type update_not_possible",
             "user", "#dependabot-ops"

        expect(chatop_response).
          not_to include(".dependabot job #{private_update_job_error.update_job_id}")
      end

      context "when queruing by date-range" do
        before do
          travel_to(25.hours.ago) do
            build_error("bundler", "json", "update_not_possible")
          end
        end

        it "excludes the old job" do
          start_time = 2.hours.ago
          end_time = Time.zone.now
          chat "dependabot update-job-errors --package-manager bundler "\
               "--error-type update_not_possible " \
               "--from #{start_time} --to #{end_time}",
               "user", "#dependabot-ops"

          expect(chatop_response).
            to include(".dependabot job #{update_job_error.update_job_id}")
          expect(chatop_response).not_to include("--dep=\"json\"")
        end
      end
    end

    context "with private repo update job errors" do
      let!(:private_update_job_error) do
        build_error("bundler", "private-gem", "update_not_possible", private: true)
      end

      let!(:public_update_job_error) do
        build_error("bundler", "public-gem", "update_not_possible")
      end

      it "returns private repo errors when --private flag is set" do
        mock_github_security_advisory_fetch(dependency_name: "private-gem", package_manager: "bundler")

        chat "dependabot update-job-errors --package-manager bundler "\
             "--error-type update_not_possible --private true",
             "user", "#dependabot-ops"

        expect(chatop_response).
          to include(".dependabot job #{private_update_job_error.update_job_id}")
        expect(chatop_response).
          not_to include(".dependabot job #{public_update_job_error.update_job_id}")
      end

      it "returns public repo errors by default" do
        mock_github_security_advisory_fetch(dependency_name: "public-gem", package_manager: "bundler")

        chat "dependabot update-job-errors --package-manager bundler "\
             "--error-type update_not_possible",
             "user", "#dependabot-ops"

        expect(chatop_response).
          to include(".dependabot job #{public_update_job_error.update_job_id}")
        expect(chatop_response).
          not_to include(".dependabot job #{private_update_job_error.update_job_id}")
      end
    end

    def build_error(package_manager, dependency, error_type, private: false)
      mock_github_security_advisory_fetch(dependency_name: dependency, package_manager:)

      repo = if private
               FactoryBot.create(:repo)
             else
               FactoryBot.create(:repo, :public)
             end
      update_config = FactoryBot.create(:update_config,
                                        repo: repo,
                                        package_manager: package_manager,)
      FactoryBot.create(:dependency_group, :applies_to_security, update_config: update_config)
      update_job = FactoryBot.create(:update_job, :security,
                                     update_config: update_config,
                                     dependencies: [dependency])

      FactoryBot.create(:update_job_error, error_type: error_type,
                                           update_job: update_job)
    end
  end
end
