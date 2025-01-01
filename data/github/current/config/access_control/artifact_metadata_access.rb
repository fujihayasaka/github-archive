# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :write_artifact_metadata do |access|
    access.ensure_context :resource
    access.allow :repo_contents_writer # to be removed
    access.allow :repo_artifact_metadata_writer
  end

  define_access :read_artifact_metadata do |access|
    access.ensure_context :resource
    access.allow :repo_contents_reader # to be removed
    access.allow :repo_artifact_metadata_reader
  end
end
