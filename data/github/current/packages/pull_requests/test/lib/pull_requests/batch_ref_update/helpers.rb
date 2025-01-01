# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./mock_command"

module PullRequests
  module BatchRefUpdate
    module Helpers
      sig do
        params(
          reason: Enums::Failures,
          pull_request_id: Integer,
          ref_name: String,
          before_sha: T.nilable(String),
          after_sha: String,
        ).returns(Request::Ineligible)
      end
      def build_ineligible_request(
        reason: Enums::Failures::AlreadyUpdated,
        pull_request_id: 1,
        ref_name: "refs/pull/1/head",
        before_sha: nil,
        after_sha: SecureRandom.hex(16)
      )
        Request::Ineligible.new(reason:, pull_request_id:, ref_name:, before_sha:, after_sha:)
      end

      sig do
        params(
          pull_request_id: Integer,
          ref_name: String,
          before_sha: T.nilable(String),
          after_sha: String,
        ).returns(Request::Eligible)
      end
      def build_eligible_request(
        pull_request_id: 1,
        ref_name: "refs/pull/1/head",
        before_sha: nil,
        after_sha: SecureRandom.hex(16)
      )
        Request::Eligible.new(pull_request_id:, ref_name:, before_sha:, after_sha:)
      end
    end
  end
end
