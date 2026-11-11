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
      fork_repository_id = fork_repository_id_for(repository: repository, pull_request: pull_request)
      head_ref = pull_request.qualified_head_ref_name
      base_ref = pull_request.qualified_base_ref_name

      begin
        check_repository_args = {
          repository_id: repository_id,
          organization_id: organization_id,
          enterprise_id: enterprise_id,
          commit_sha: pr_sha,
          base_sha: merge_base,
          pull_request_id: pr_id,
          pull_request_number: pr_number,
          head_ref: head_ref,
          base_ref: base_ref,
        }
        check_repository_args[:fork_repository_id] = fork_repository_id if fork_repository_id

        response = client.check_repository(**check_repository_args)
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
          "gh.pull_request.head_ref": head_ref,
          "gh.pull_request.base_ref": base_ref,
          "gh.pull_request.fork_repository_id": fork_repository_id,
          "gh.license_compliance.results.status": status.to_s,
        )

        case status
        when :REPOSITORY_CHECK_STATUS_PASS
          return true, ""
        when :REPOSITORY_CHECK_STATUS_FAIL
          return false, "License compliance has detected a non-compliant dependency blocking this code from being merged."
        when :REPOSITORY_CHECK_STATUS_PENDING
          return false, "License compliance check waiting for results"
        when :REPOSITORY_CHECK_STATUS_UNKNOWN
          return false, "License compliance check unexpected result"
        when :REPOSITORY_CHECK_STATUS_ERROR
          message = "License compliance check errored. See the license compliance check run for more details."
          return false, message
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
            "gh.pull_request.head_ref": head_ref,
            "gh.pull_request.base_ref": base_ref,
            "gh.pull_request.fork_repository_id": fork_repository_id,
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

    def self.fork_repository_id_for(repository:, pull_request:)
      head_repository_id = pull_request.head_repository_id
      return nil if head_repository_id.nil? || head_repository_id == repository.id

      head_repository_id
    end
    private_class_method :fork_repository_id_for
  end
end
