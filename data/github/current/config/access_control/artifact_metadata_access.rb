# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :write_artifact_metadata do |access|
    access.ensure_context :resource
    access.allow :repo_artifact_metadata_writer
  end

  define_access :read_artifact_metadata do |access|
    access.ensure_context :resource
    access.allow :repo_artifact_metadata_reader
  end

  define_access :write_org_artifact_metadata do |access|
    access.ensure_context :resource
    access.allow :org_artifact_metadata_writer
  end

  define_access :read_org_artifact_metadata do |access|
    access.ensure_context :resource
    access.allow :org_artifact_metadata_reader
  end
end
