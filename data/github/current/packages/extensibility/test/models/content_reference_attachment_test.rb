# typed: true
# frozen_string_literal: true

require "test_helper"

class ContentReferenceAttachmentTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @reference = create(:content_reference)
    @integration = create(:integration)
  end

  test "can only create one attachment per integration per reference" do
    attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: @integration, title: "test title", body: "test unfurl body")
    assert_predicate attachment, :valid?
    assert attachment.save

    new_attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: @integration, title: "test title", body: "test unfurl body")
    refute new_attachment.save
    refute_predicate new_attachment, :valid?
    assert_equal new_attachment.errors.full_messages[0], "Integration can only have one attachment per content reference"

    new_integration = create(:integration)
    new_attachment.integration = new_integration
    assert new_attachment.save
    assert_predicate new_attachment, :valid?
  end

  test "prevent duplicate attachments per integration per reference on update" do
    attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: @integration, title: "test title", body: "test unfurl body")
    assert_predicate attachment, :valid?
    assert attachment.save

    new_integration = create(:integration)
    new_attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: new_integration, title: "test title", body: "test unfurl body")
    assert_predicate new_attachment, :valid?
    assert new_attachment.save

    attachment.integration = new_integration
    refute attachment.save
    refute_predicate attachment, :valid?
    assert_equal attachment.errors.full_messages[0], "Integration can only have one attachment per content reference"
  end

  test "title should be less than 1024 bytes" do
    # this character is a 3 byte unicode sequence
    mb_str = "漢"
    ascii_str = "a"

    expected_bytes = ContentReferenceAttachment::TITLE_BYTESIZE_LIMIT
    expected_characters = expected_bytes / 4

    attachment = ContentReferenceAttachment.create(content_reference: @reference, integration: @integration, title: "test title", body: "test unfurl body")
    attachment.title = mb_str * (expected_bytes / 3 + 1).to_i
    refute attachment.save
    refute_predicate attachment, :valid?, "#{attachment.errors.full_messages}"
    assert_equal attachment.errors.full_messages[0], "Title is too long (maximum is #{expected_characters} characters)"

    attachment.title = mb_str * (expected_bytes / 3).to_i
    assert attachment.save
    assert_predicate attachment, :valid?

    attachment.title = ascii_str * (expected_bytes + 1)
    refute attachment.save
    refute_predicate attachment, :valid?, "#{attachment.errors.full_messages}"
    assert_equal attachment.errors.full_messages[0], "Title is too long (maximum is #{expected_characters} characters)"

    attachment.title = ascii_str * expected_bytes
    assert attachment.save
    assert_predicate attachment, :valid?
  end

  test "title should be UTF-8" do
    attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: @integration, body: "test unfurl body")
    title = "Have a glass of \xF0\x9F\x8D\xB7"

    attachment.title = title
    assert attachment.save
    attachment.reload
    assert_equal Encoding::UTF_8, attachment.title.encoding
    assert_equal title, attachment.title
  end

  test "body should be less than 262144 bytes" do
    attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: @integration, title: "test unfurl title")

    expected_bytes = MYSQL_UNICODE_BLOB_LIMIT
    expected_characters = expected_bytes / 4
    body = "a" * (expected_bytes + 1)

    attachment.body = body
    assert !attachment.valid?, "#{attachment.errors.full_messages}"
    assert_equal attachment.errors.full_messages[0], "Body is too long (maximum is #{expected_characters} characters)"
  end

  test "bodies should be UTF-8" do
    attachment = ContentReferenceAttachment.new(content_reference: @reference, integration: @integration, title: "test unfurl title")
    body = "Have a glass of \xF0\x9F\x8D\xB7"

    attachment.body = body
    assert attachment.save
    attachment.reload
    assert_equal Encoding::UTF_8, attachment.body.encoding
    assert_equal body, attachment.body
  end

  test "content_reference cannot be too old" do
    Timecop.travel(7.hours) do
      attachment = ContentReferenceAttachment.create(content_reference: @reference, integration: @integration, title: "test title", body: "test unfurl body")
      assert !attachment.valid?, "#{attachment.errors.full_messages}"
      assert_equal attachment.errors.full_messages[0], "Content reference is older than 6 hours"
    end
  end

  test "for_integration returns all content attachments created by the integration" do
    10.times do
      reference = create(:content_reference)
      create(:content_reference_attachment, content_reference: reference, integration: @integration, title: "test title", body: "test unfurl body")
    end

    assert_equal 10, ContentReferenceAttachment.for_integration_id(@integration.id).count
  end
end
