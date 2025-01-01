# typed: true
# frozen_string_literal: true

module OSSLicenseCompliance
  class RepositoryLicenseCompliance
    def self.check_compliance(repository:, pull_request:)
      # This check is optimistic and reports the license compliance check as successful
      # if anything causes the check to not run or not complete to avoid blocking PRs.
      client = OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new

      repository_id = repository.id
      organization_id = repository.organization&.id
      enterprise_id = repository.organization&.business&.id
      pr_sha = pull_request.head_sha
      merge_base = pull_request.merge_base
      pr_number = pull_request.number
      pr_id = pull_request.id

      begin
        response = client.check_repository(
          repository_id: repository_id,
          organization_id: organization_id,
          enterprise_id: enterprise_id,
          commit_sha: pr_sha,
          base_sha: merge_base,
          pull_request_id: pr_id,
          pull_request_number: pr_number
        )
        status = response.status
        GitHub.logger.info(
          "License compliance check completed",
          "code.namespace": "OSSLicenseCompliance::RepositoryLicenseCompliance",
          "code.function": "check_compliance",
          "gh.repository.id": repository_id,
          "gh.organization.id": organization_id,
          "gh.enterprise.id": enterprise_id,
          "gh.pull_request.sha": pr_sha,
          "gh.pull_request.id": pr_id,
          "gh.pull_request.number": pr_number,
          "gh.license_compliance.results.status": status.to_s,
        )

        case status
        when :REPOSITORY_CHECK_STATUS_PASS
          return true, ""
        when :REPOSITORY_CHECK_STATUS_FAIL
          return false, "License compliance check failed"
        when :REPOSITORY_CHECK_STATUS_PENDING
          return false, "License compliance check waiting for results"
        when :REPOSITORY_CHECK_STATUS_UNKNOWN
          return false, "License compliance check unexpected result"
        else
          # Unexpected statuses are failures. This shouldn't happen, so we'd want to be made aware
          # of issues by having failures reported.
          GitHub.logger.error(
            "License compliance check invalid/unknown result",
            "code.namespace": "OSSLicenseCompliance::RepositoryLicenseCompliance",
            "code.function": "check_compliance",
            "gh.repository.id": repository_id,
            "gh.organization.id": organization_id,
            "gh.enterprise.id": enterprise_id,
            "gh.pull_request.sha": pr_sha,
            "gh.pull_request.id": pr_id,
            "gh.pull_request.number": pr_number,
            "gh.license_compliance.results.status": status.to_s,
          )
          return false, "License compliance check invalid result"
        end
      rescue OSSLicenseCompliance::Twirp::InvalidArgumentError
        GitHub.logger.info(
          "No license policy found in Oss License Compliance",
          "code.namespace": "OSSLicenseCompliance::RepositoryLicenseCompliance",
          "code.function": "check_compliance",
          "gh.repository.id": repository_id,
          "gh.organization.id": organization_id,
          "gh.enterprise.id": enterprise_id,
          "gh.pull_request.sha": pr_sha,
        )
      end
      [false, "No license check result"]
    end
  end
end
