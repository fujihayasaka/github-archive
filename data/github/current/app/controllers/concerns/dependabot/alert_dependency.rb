# typed: true
# frozen_string_literal: true

module Dependabot
  module AlertDependency
    REPO_FILTER_NAME = "repo"
    SEVERITY_FILTER_NAME = "severity"
    PACKAGE_FILTER_NAME = "package"
    ECOSYSTEM_FILTER_NAME = "ecosystem"
    MANIFEST_FILTER_NAME = "manifest"
    RESOLUTION_FILTER_NAME = "resolution"
    CVE_ID_FILTER_NAME = "cve_id"
    GHSA_ID_FILTER_NAME = "ghsa_id"
    EPSS_FILTER_NAME = "epss"
    ARTIFACT_REGISTRY_URL_FILTER_NAME = "artifact_registry_url"
    STATE_CHANGE_COMMENT_MAX_LENGTH = 280

    def normalize_comment(comment)
      return nil if comment.nil? || comment.empty?
      comment.encode("UTF-8", universal_newline: true)
    end
  end
end
