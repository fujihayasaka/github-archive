# typed: true
# frozen_string_literal: true

require "test_helper"

class GistEditorViewTest < GitHub::TestCase
  fixtures do
    @staff_user = create :staff_admin_user

    contents = [
      { name: "placeholder", value: "." },
    ]

    @gist = GistHelpers.generate(user: @staff_user, contents: contents)
    @blob = @gist.files.first.freeze
  end

  context "markdown_file?" do
    test "correctly identifies GitHub-supported markdown extensions" do
      markdown_filenames = [
        "test.md",
        "test.mkdn",
        "test.markdown",
        "test.mdown",
        "test.mkd"
      ]

      non_markdown_filenames = [
        "test.mark",
        "test.txt",
        "test",
        "mdown",
        "md"
      ]

      markdown_filenames.each do |filename|
        view = Gists::EditorView.new(
          gist: @gist,
          blob: @blob,
          filename: filename)
        assert view.markdown_file?
      end

      non_markdown_filenames.each do |filename|
        view = Gists::EditorView.new(
          gist: @gist,
          blob: @blob,
          filename: filename)
        refute view.markdown_file?
      end
    end
  end

  test "#asset_types" do
    view = Gists::EditorView.new(gist: @gist)
    assert_equal([:assets], view.asset_types)
  end
end
