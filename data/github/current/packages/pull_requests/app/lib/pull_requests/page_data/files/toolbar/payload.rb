# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::Toolbar
  class Payload
    class SplitPreference < T::Enum
      enums do
        # TODO we should update these values to be UPCASE to match ENUMS elsewhere in PullRequests code, but that requires client code changes.
        # discussion link https://github.com/github/pull-requests/discussions/9767#discussioncomment-9885181 which led to doing this for all ENUMs
        Split = new("split")
        Unified = new("unified")
      end
    end

    class PullRequest < T::Struct
      const :id, Integer
      const :pathName, String
    end

    class DiffViewSettings < T::Struct
      const :hideWhitespace, T::Boolean
      const :lineSpacing, String
      const :splitPreference, SplitPreference
    end

    class Toolbar < T::Struct
      const :annotations, T::Array[PullRequests::PageData::Annotations::Payload::Annotation]
      const :hostUrl, String
      const :pullRequest, PullRequest
      const :repositoryId, Numeric
      const :threadPreviews, T::Array[PullRequests::PageData::ThreadPreviews::Payload::ThreadPreview]
      const :totalFilesCount, Numeric
      const :viewedFilesCount, Numeric
      const :viewSettings, DiffViewSettings
    end

    sig do
      params(
        toolbar_data: PullRequests::PageData::Files::Toolbar::Loader::Data
      ).returns(Toolbar)
    end
    def self.call(toolbar_data)
      new.call(toolbar_data)
    end

    sig do
      params(
        toolbar_data: PullRequests::PageData::Files::Toolbar::Loader::Data
      ).returns(Toolbar)
    end
    def call(toolbar_data)
      Toolbar.new(
        annotations: PullRequests::PageData::Annotations::Payload.call(toolbar_data.annotations),
        hostUrl: toolbar_data.host_url,
        pullRequest: PullRequest.new(
          id: toolbar_data.pull_request.id,
          pathName: toolbar_data.pull_request.path_name
        ),
        repositoryId: toolbar_data.repository_id,
        threadPreviews: PullRequests::PageData::ThreadPreviews::Payload.call(toolbar_data.thread_previews),
        totalFilesCount: toolbar_data.total_files_count,
        viewedFilesCount: PullRequests::PageData::ViewedFilesCount::Payload.call(toolbar_data.viewed_files_count).viewedFilesCount,
        viewSettings: DiffViewSettings.new(
          hideWhitespace: toolbar_data.view_settings.hide_whitespace,
          lineSpacing: toolbar_data.view_settings.line_spacing,
          splitPreference: SplitPreference.deserialize(toolbar_data.view_settings.split_preference.serialize)
        )
      )
    end
  end
end
