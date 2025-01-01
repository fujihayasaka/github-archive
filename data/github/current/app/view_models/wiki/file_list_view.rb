# typed: strict
# frozen_string_literal: true

module Wiki
  class FileListView < Diff::FileListView
    self.file_view_class = Wiki::FileView
  end
end
