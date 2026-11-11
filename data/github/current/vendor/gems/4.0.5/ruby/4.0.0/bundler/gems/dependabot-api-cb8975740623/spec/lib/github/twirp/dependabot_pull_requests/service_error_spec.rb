# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::DependabotPullRequests::ServiceError do
  let(:error_type) { MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REPO_NOT_FOUND }
  let(:inner_error) do
    MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
      type: error_type,
      message: "error"
    )
  end
  let(:err) { described_class.new("test", inner_error, pull_request) }
  let(:pull_request) { nil }

  describe "#message" do
    it "is the outer error's message" do
      expect(err.message).to eq("test")
    end
  end

  describe "#pull_request" do
    context "when a pull request is given to the error" do
      let(:pull_request) do
        MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
          base_ref: "main",
          base_sha: "1234567",
          github_number: 1,
          has_user_commits: false,
          repository_id: 1,
          state: "open"
        )
      end

      it "is the pull request" do
        expect(err.pull_request).to eq(pull_request)
      end
    end

    it "is nil if a pull request is not given to the error" do
      expect(err.pull_request).to be_nil
    end
  end

  describe "#error" do
    it "is the inner api response error" do
      expect(err.error).to eq(inner_error)
    end
  end

  describe "#details" do
    it "is the inner api response error's message" do
      expect(err.details).to eq("error")
    end
  end

  describe "#type" do
    it "is the inner api response error's type as a symbol" do
      expect(err.type).to eq(err.resolve_api_error_symbol(inner_error.type))
    end
  end

  describe "#pull_request_was_created?" do
    context "with a pull request with an assigned number" do
      let(:pull_request) do
        MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
          base_ref: "main",
          base_sha: "1234567",
          github_number: 1,
          has_user_commits: false,
          repository_id: 1,
          state: "open"
        )
      end

      it "is true" do
        expect(err.pull_request_was_created?).to be(true)
      end
    end

    context "with a nil pull request" do
      it "is false" do
        expect(err.pull_request_was_created?).to be(false)
      end
    end

    context "with a pull request without an assigned number" do
      let(:pull_request) { MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new }

      it "is false" do
        expect(err.pull_request_was_created?).to be(false)
      end
    end
  end

  describe ".for_error" do
    MonolithTwirp::Dependabot::PullRequests::V1::ErrorType.constants.each do |error_symbol|
      error_type = MonolithTwirp::Dependabot::PullRequests::V1::ErrorType.const_get(error_symbol)

      describe "with a #{error_symbol} response error type" do
        let(:response_error) do
          MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
            type: error_type,
            message: "error",
          )
        end

        let(:error_class) do
          if error_type == MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_DEPENDABOT_NOT_INSTALLED
            GitHub::Twirp::DependabotPullRequests::DependabotNotInstalledError
          elsif GitHub::Twirp::DependabotPullRequests::ServiceError::REPO_STATE_ERROR_TYPES.include?(error_type)
            GitHub::Twirp::DependabotPullRequests::RepoStateServiceError
          elsif GitHub::Twirp::DependabotPullRequests::ServiceError::NON_TRANSIENT_ERROR_TYPES.include?(error_type)
            described_class
          else
            GitHub::Twirp::DependabotPullRequests::TransientServiceError
          end
        end

        it "raises the expected error class" do
          expect(described_class.for_error("test", response_error)).to be_a(error_class)
        end
      end
    end
  end
end
