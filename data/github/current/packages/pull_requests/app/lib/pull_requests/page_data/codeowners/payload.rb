# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Codeowners
  class Payload

    class PathOwnership < T::Struct
      const :isOwnedByViewer, T::Boolean
      const :owners, T::Array[String]
      # Rule line number and url are only nil when path is unowned
      const :ruleLineNumber, T.nilable(Integer)
      const :ruleUrl, T.nilable(String) # permalink to line in CODEOWNERS file
    end

    class Payload < T::Struct
      const :isEnabled, T::Boolean
      const :isViewerOneOfMultipleCodeowners, T::Boolean
      const :ownershipByPath, T::Hash[String, T::untyped]
    end

    sig do
      params(loader_data: PullRequests::PageData::Codeowners::Loader::Data).returns(Payload)
    end
    def self.call(loader_data)
      new.call(loader_data)
    end

    sig do
      params(loader_data: PullRequests::PageData::Codeowners::Loader::Data).returns(Payload)
    end
    def call(loader_data)
      is_viewer_one_of_multiple_codeowners = T.let(false, T::Boolean)
      viewer_has_owned_files = T.let(false, T::Boolean)
      viewer_has_unowned_files = T.let(false, T::Boolean)
      ownership_by_path = {}

      loader_data.ownership_by_path.map do |path, info|
        viewer_has_owned_files ||= !!info.is_owned_by_viewer
        viewer_has_unowned_files ||= !info.is_owned_by_viewer

        ownership_by_path[path] = PathOwnership.new(
          isOwnedByViewer: info.is_owned_by_viewer,
          owners: info.owners,
          ruleLineNumber: info.rule_line_number,
          ruleUrl: info.rule_url,
        )
      end

      # The codeowners filter should only be visible if the user owns at least 1, but not all files in the PR.
      if viewer_has_owned_files && viewer_has_unowned_files
        is_viewer_one_of_multiple_codeowners = true
      end

      Payload.new(
        isEnabled: loader_data.is_enabled,
        isViewerOneOfMultipleCodeowners: is_viewer_one_of_multiple_codeowners,
        ownershipByPath: ownership_by_path,
      )
    end
  end
end
