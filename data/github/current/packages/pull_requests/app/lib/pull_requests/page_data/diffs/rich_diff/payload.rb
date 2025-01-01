# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::RichDiff
  class Payload
    class FileRendererBlobData < T::Struct
      const :identityUuid, String
      const :size, Integer
      const :type, String
      const :url, String
    end

    class RichDiff < T::Struct
      const :canToggleRichDiff, T::Boolean
      const :defaultToRichDiff, T::Boolean
      const :proseDiffHtml, T.nilable(String)
      const :renderInfo, T.nilable(FileRendererBlobData)
      const :dependencyDiffPath, T.nilable(String)
    end

    sig do
      params(data: T.nilable(PullRequests::PageData::Diffs::RichDiff::Loader::Data)).returns(T.nilable(RichDiff))
    end
    def self.call(data)
      new.call(data)
    end

    sig do
      params(data: T.nilable(PullRequests::PageData::Diffs::RichDiff::Loader::Data)).returns(T.nilable(RichDiff))
    end
    def call(data)
      return nil if data.nil?
      return nil if !data.default_to_rich_diff && !data.can_toggle_rich_diff

      unless data.render_info.nil?
        render_info = FileRendererBlobData.new(
          identityUuid: T.must(data.render_info).identity_uuid,
          size: T.must(data.render_info).size,
          type: T.must(data.render_info).type,
          url: T.must(data.render_info).url
        )
      end

      RichDiff.new(
        canToggleRichDiff: data.can_toggle_rich_diff,
        defaultToRichDiff: data.default_to_rich_diff,
        proseDiffHtml: data.prose_diff_html,
        dependencyDiffPath: data.dependency_diff_path,
        renderInfo: render_info
      )
    end
  end
end
