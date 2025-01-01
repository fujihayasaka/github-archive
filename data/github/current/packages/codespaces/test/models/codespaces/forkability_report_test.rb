# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class ForkabilityReportTest < GitHub::TestCase
    fixtures do
      @monalisa = create(:paid_user, name: "monalisa")

      admin = create(:user, login: "admin-user")
      @org = create(:codespaces_organization, admin: admin)
      @public_repo = create(:repository, owner: @org)

      @personal_repo = create(:repository, owner: @monalisa)
    end

    context "Report for public repo", skip_enterprise: true do
      test "requires a fork" do
        report = Codespaces::ForkabilityReport.new(repo: @public_repo, user: @monalisa)
        assert report.requires_fork?
      end

      test "reports it's not forked yet" do
        report = Codespaces::ForkabilityReport.new(repo: @public_repo, user: @monalisa)
        refute report.fork_already_exists?
      end
    end

    context "Report for personal repo", skip_enterprise: true do
      test "does not require a fork" do
        report = Codespaces::ForkabilityReport.new(repo: @personal_repo, user: @monalisa)
        refute report.requires_fork?
      end

      test "reports it's not forked" do
        report = Codespaces::ForkabilityReport.new(repo: @public_repo, user: @monalisa)
        refute report.fork_already_exists?
      end
    end

    context "Report for forked repo", skip_enterprise: true do
      test "does not require a fork" do
        fork = create(:fork_repository, forker: @monalisa, fork_repo: @public_repo)
        flunk("Failed to fork repo") unless fork

        report = Codespaces::ForkabilityReport.new(repo: fork, user: @monalisa)
        refute report.requires_fork?
      end

      test "reports it is forked" do
        fork = create(:fork_repository, forker: @monalisa, fork_repo: @public_repo)
        flunk("Failed to fork repo") unless fork

        report = Codespaces::ForkabilityReport.new(repo: fork, user: @monalisa)
        assert report.fork_already_exists?
      end
    end

    context "Report for public repo after it's been forked", skip_enterprise: true do
      test "does not require a fork" do
        fork = create(:fork_repository, forker: @monalisa, fork_repo: @public_repo)
        flunk("Failed to fork repo") unless fork

        report = Codespaces::ForkabilityReport.new(repo: @public, user: @monalisa)
        assert report.requires_fork?
      end

      test "reports it is forked" do
        fork = create(:fork_repository, forker: @monalisa, fork_repo: @public_repo)
        flunk("Failed to fork repo") unless fork

        report = Codespaces::ForkabilityReport.new(repo: @public_repo, user: @monalisa)
        assert report.fork_already_exists?
      end
    end

    context "serialization", skip_enterprise: true do
      test "converts report to json" do
        report = Codespaces::ForkabilityReport.new(repo: @public_repo, user: @monalisa)
        assert_equal report.to_json, "{\"fork_required\":true,\"fork_already_exists\":false}"
      end

      test "converts to hash" do
        report = Codespaces::ForkabilityReport.new(repo: @public_repo, user: @monalisa)
        assert_equal report.to_h, { fork_required: true, fork_already_exists: false }
      end
    end
  end
end
