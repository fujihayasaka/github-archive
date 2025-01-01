# typed: true
# frozen_string_literal: true

require_relative "../../fast_test_helper"

class Localization::AzureTranslations::HtmlSplitterTest < GitHub::TestCase
  setup do
    SecureRandom.stubs(:uuid).returns("1", "2", "3", "4")
  end

  test "does not split if lenght is same as limit" do
    html = "<div>hello</div>"

    result = split(html, max_length: html.length)

    assert_equal 1, result.length
    assert_unsplits(result, html)
  end

  test "splits by max length" do
    html = <<~HTML
      <div>
        <p>This is the first paragraph.</p>
        <p>This is the second paragraph.</p>
        <p>This is the third paragraph.</p>
      </div>
    HTML

    expected_frame = <<~HTML
      <div>
        <span data-tph="s1"></span>
        <span data-tph="s2"></span>
        <span data-tph="s3"></span>
      </div>
    HTML

    fragment1 = <<~HTML
      <div>
        <p data-tph="s1">This is the first paragraph.</p>
        <p data-tph="s2">This is the second paragraph.</p>
      </div>
    HTML

    fragment2 = <<~HTML
      <div>
        <p data-tph="s3">This is the third paragraph.</p>
      </div>
    HTML

    result = split(html, max_length: 110)

    assert_same_html(expected_frame, result.pieces[0])
    assert_same_html(fragment1, result.pieces[1])
    assert_same_html(fragment2, result.pieces[2])
    assert_equal 3, result.length
    assert_unsplits(result, html)
  end

  test "splits an actual discussion comment" do
    html = read_fixture("packages/localization/test/fixtures/azure_translations/html_splitter/huge_html.html")

    result = split(html, max_length: 50_000)

    assert_unsplits(result, html)
  end

  test "raises when it is not possible to split" do
    html = <<~HTML
      <div>
        <p>This is the first paragraph.</p>
      </div>
    HTML

    error = assert_raises(Localization::AzureTranslations::HtmlSplitter::SplitError) do
      split(html, max_length: 10)
    end

    assert_equal "Content is too long. Cannot split content into chunks of 10 chars.", error.message
  end

  private

  def split(html, max_length: 10)
    Localization::AzureTranslations::HtmlSplitter.new(max_length: max_length).split(html)
  end

  def assert_same_html(expected, actual)
    assert_equal(normalize_html(expected), normalize_html(actual))
  end

  def assert_unsplits(result, expected_html)
    assert_same_html(normalize_html(result.join), normalize_html(expected_html))
  end

  def normalize_html(html)
    html.gsub(/^\s+</, "<").gsub(/></, ">\n<").strip
  end

  def read_fixture(file)
    File.read(Rails.root.join(file))
  end
end
