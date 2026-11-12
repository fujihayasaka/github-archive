# frozen_string_literal: true

require "spec_helper"
require "dependabot/exception_scrubber"

RSpec.describe Dependabot::ExceptionScrubber do
  context "when in cloud environments" do
    it "scrubs sensitive repo NWO data from an api url" do
      message = "POST https://api.github.com/repos/foo/bar/issues/2/assignees: 422"
      expected_message = "POST https://api.github.com/repos/foo/[FILTERED_REPO]/issues/2/assignees: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters nwo from a bare repo api url" do
      message = "POST https://api.github.com/repos/foo/bar: 404"
      expected_message = "POST https://api.github.com/repos/foo/[FILTERED_REPO]: 404"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "scrubs sensitive repo NWO data from an internal api url" do
      message = "POST https://internal-api.service.iad.github.net/repos/foo/bar/issues/2/assignees: 422"
      expected_message =
        "POST https://internal-api.service.iad.github.net/repos/foo/[FILTERED_REPO]/issues/2/assignees: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "scrubs sensitive repo NWO data from a bare internal api url" do
      message = "POST https://internal-api.service.iad.github.net/repos/foo/bar: 422"
      expected_message = "POST https://internal-api.service.iad.github.net/repos/foo/[FILTERED_REPO]: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters nwo from a web url" do
      message = "POST https://github.com/foo/bar/issues/2/assignees: 422"
      expected_message = "POST https://github.com/foo/[FILTERED_REPO]/issues/2/assignees: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters nwo from a bare web url" do
      message = "POST https://github.com/foo/bar: 404"
      expected_message = "POST https://github.com/foo/[FILTERED_REPO]: 404"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters an nwo with special characters" do
      message = "POST https://github.com/foo-org/bar.service: 404"
      expected_message = "POST https://github.com/foo-org/[FILTERED_REPO]: 404"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters multiple, unique repositories" do
      message = "Found https://github.com/foo/bar and https://api.github.com/repos/foo/private and github.com/foo/baz"
      expected_message =
        "Found https://github.com/foo/[FILTERED_REPO] and https://api.github.com/repos/foo/[FILTERED_REPO] and "\
        "github.com/foo/[FILTERED_REPO]"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "does not filter api URLs using IDs" do
      message = "POST https://api.github.com/repositories/123"

      expect(scrubbed_message(message)).to eq(message)
    end

    it "filters branch refs" do
      message =
        "DELETE https://api.github.com/repositories/12345/git/refs/heads/dependabot/npm_and_yarn/" \
        "minimatch-and-aws-cdk/aws-autoscaling-and-aws-cdk/aws-autoscaling-hooktargets-and-aws-cdk/" \
        "aws-ec2-and-aws-cdk/aws-iam-and-aws-cdk/aws-lambda-and-aws-cdk/aws-sns-and-aws-cdk/" \
        "aws-sns-subscriptions-and-aws-cdk/core-and-aws-cdk/assert-3.1.2: 500"
      expected_message = "DELETE https://api.github.com/repositories/12345/git/refs/[FILTERED_REF]: 500"

      expect(scrubbed_message(message)).to eq(expected_message)
    end
  end

  context "when in Proxima environments" do
    it "scrubs sensitive repo NWO data from an api url" do
      message = "POST https://api.my-tenant.ghe.com/repos/foo/bar/issues/2/assignees: 422"
      expected_message =
        "POST https://api.[FILTERED_TENANT].ghe.com/repos/[FILTERED_NWO]/[FILTERED_NWO]/issues/2/assignees: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters nwo from a bare repo api url" do
      message = "POST https://api.my-tenant.ghe.com/repos/foo/bar: 404"
      expected_message = "POST https://api.[FILTERED_TENANT].ghe.com/repos/[FILTERED_NWO]/[FILTERED_NWO]: 404"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "scrubs sensitive repo NWO data from an internal api url" do
      message =
        "POST http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/" \
        "repos/foo/bar/issues/2/assignees: 422"
      expected_message =
        "POST http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repos/[FILTERED_NWO]/" \
        "[FILTERED_NWO]/issues/2/assignees: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "scrubs sensitive repo NWO data from a bare internal api url" do
      message = "POST http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repos/foo/bar: 422"
      expected_message =
        "POST http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repos/" \
        "[FILTERED_NWO]/[FILTERED_NWO]: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters nwo from a web url" do
      message = "POST https://my-tenant.ghe.com/foo/bar/issues/2/assignees: 422"
      expected_message = "POST https://[FILTERED_TENANT].ghe.com/[FILTERED_NWO]/[FILTERED_NWO]/issues/2/assignees: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters nwo from a bare web url" do
      message = "POST https://my-tenant.ghe.com/foo/bar: 404"
      expected_message = "POST https://[FILTERED_TENANT].ghe.com/[FILTERED_NWO]/[FILTERED_NWO]: 404"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters an nwo with special characters" do
      message = "POST https://my-tenant.ghe.com/foo-org/bar.service: 404"
      expected_message = "POST https://[FILTERED_TENANT].ghe.com/[FILTERED_NWO]/[FILTERED_NWO]: 404"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters multiple, unique repositories" do
      message =
        "Found https://my-tenant.ghe.com/foo/bar and https://api.my-tenant.ghe.com/repos/foo/private " \
        "and my-tenant.ghe.com/foo/baz"
      expected_message =
        "Found https://[FILTERED_TENANT].ghe.com/[FILTERED_NWO]/[FILTERED_NWO] and " \
          "https://api.[FILTERED_TENANT].ghe.com/repos/[FILTERED_NWO]/[FILTERED_NWO] and "\
          "[FILTERED_TENANT].ghe.com/[FILTERED_NWO]/[FILTERED_NWO]"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "does not filter api URLs using IDs except for the tenant" do
      message = "POST https://api.my-tenant.ghe.com/repositories/123"
      expected_message = "POST https://api.[FILTERED_TENANT].ghe.com/repositories/123"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters branch refs" do
      message =
        "DELETE http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repositories/12345/git/refs/" \
        "heads/dependabot/npm_and_yarn/minimatch-and-aws-cdk/aws-autoscaling-and-aws-cdk/" \
        "aws-autoscaling-hooktargets-and-aws-cdk/aws-ec2-and-aws-cdk/aws-iam-and-aws-cdk/" \
        "aws-lambda-and-aws-cdk/aws-sns-and-aws-cdk/aws-sns-subscriptions-and-aws-cdk/" \
        "core-and-aws-cdk/assert-3.1.2: 500"
      expected_message =
        "DELETE http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repositories/12345/" \
        "git/refs/[FILTERED_REF]: 500"

      expect(scrubbed_message(message)).to eq(expected_message)
    end

    it "filters collaborator permission check user names" do
      message =
        "POST http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repositories/123/" \
        "collaborators/my-user/permission: 422"
      expected_message =
        "POST http://unicorn-internal-api.github-prod-weu-01.svc.cluster.local/repositories/123/" \
        "collaborators/[FILTERED_LOGIN]/permission: 422"

      expect(scrubbed_message(message)).to eq(expected_message)
    end
  end

  private

  def scrubbed_message(message)
    Dependabot::ExceptionScrubber.call(message)
  end
end
