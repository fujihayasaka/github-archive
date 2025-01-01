# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsBlobViewTest < GitHub::TestCase
  fixtures do
    @staff_user = create :staff_admin_user

    contents = [
      { name: "hello.rb", value: "def hello; puts 'Hello!'; end" },
    ]

    @gist = GistHelpers.generate(user: @staff_user, contents: contents)
  end

  setup do
    @blob = @gist.files.first
  end

  context "updatable?" do
    test "doesn't allow anonymous gists to be updated" do
      @gist.user = nil
      view = Gists::BlobView.new(gist: @gist, blob: @blob)
      refute view.updatable?
    end

    test "doesn't allow snippets to be updated" do
      @blob.stubs(:snippet?).returns(true)
      view = Gists::BlobView.new(gist: @gist, blob: @blob)
      refute view.updatable?
    end

    test "doesn't allow gists being embedded to be updated" do
      view = Gists::BlobView.new(gist: @gist, blob: @blob, embedded: true)
      refute view.updatable?
    end

    test "doesn't allow gists that use render to be updated" do
      view = Gists::BlobView.new(gist: @gist, blob: @blob)
      view.stubs(:use_render?).returns(false)
      refute view.updatable?
    end

    test "doesn't allow binary blobs to be updated" do
      @blob.stubs(:binary?).returns(true)
      view = Gists::BlobView.new(gist: @gist, blob: @blob)
      refute view.updatable?
    end

    test "doesn't allow image blobs to be updated" do
      @blob.stubs(:image?).returns(true)
      view = Gists::BlobView.new(gist: @gist, blob: @blob)
      refute view.updatable?
    end

    test "allows anyone who can admin the gist to update" do
      view = Gists::BlobView.new(gist: @gist, blob: @blob, current_user: @gist.owner)
      assert view.updatable?
    end

    test "does not allow arbitary staff members to update" do
      staff = create(:staff_admin_user)
      view = Gists::BlobView.new(gist: @gist, blob: @blob, current_user: staff)

      refute view.updatable?
    end
  end

  context "with binary ASCII-8BIT encoded file name strings" do
    test "does not raise Encoding::CompatibilityError for anchor method" do
      contents = [
        { name: "ascii_hello.rb", value: "def hello; puts 'Hello!'; end" },
      ]

      ascii_gist = GistHelpers.generate(user: @staff_user, contents: contents)
      ascii_blob = ascii_gist.files.first

      # Simulate unexpectedly receiving a Gist with ASCII-8BIT
      ascii_blob.info["name"] = "ascii_hello.rb".encode("ascii-8bit")
      ascii_blob.info["path"] = "ascii_hello.rb".encode("ascii-8bit")

      view = Gists::BlobView.new(gist: ascii_gist, blob: ascii_blob, current_user: @gist.owner)

      anchor = T.let(nil, T.nilable(String))
      assert_nothing_raised do
        anchor = view.anchor
      end
      assert_equal anchor, "file-ascii_hello-rb"
    end

    test "transliterates non-ascii characters in strings for anchor" do
      contents = [
        { name: "ascii_hello.rb", value: "def hello; puts 'Hello!'; end" },
      ]

      ascii_gist = GistHelpers.generate(user: @staff_user, contents: contents)
      ascii_blob = ascii_gist.files.first

      # Simulate unexpectedly receiving a Gist with ASCII-8BIT
      ascii_blob.info["name"] = "ascii with ü 统一.rb".b
      ascii_blob.info["path"] = "ascii with ü 统一.rb".b

      view = Gists::BlobView.new(gist: ascii_gist, blob: ascii_blob, current_user: @gist.owner)

      anchor = T.let(nil, T.nilable(String))
      assert_nothing_raised do
        anchor = view.anchor
      end
      assert_equal anchor, "file-ascii-with-u-rb"
    end
  end
end
