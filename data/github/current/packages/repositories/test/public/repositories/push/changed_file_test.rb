# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Push::ChangedFileTest < GitHub::TestCase
  context "different states of changed file" do
    test "addition" do
      repository = build(:repository)
      oid = SecureRandom.hex(32)
      previous_oid = SecureRandom.hex(32)

      file = Repositories::Push::ChangedFile.new(
        repository: repository,
        ref: "refs/heads/main",
        oid: oid,
        previous_oid: previous_oid,
        change_type: Repositories::Push::ChangedFile::ADDITION,
        path: "path.txt",
        previous_path: nil,
        score: 0
      )

      assert file.addition?
      assert_equal "A", file.change_type
      assert_equal "path.txt", file.path

      refute file.big?
      assert_equal "refs/heads/main", file.ref
      assert_equal repository, file.repository
      assert_equal oid, file.oid
      assert_equal oid, file.sha
      assert_equal previous_oid, file.previous_oid
      assert_equal previous_oid, file.before
    end

    test "deletion" do
      file = Repositories::Push::ChangedFile.new(
        change_type: Repositories::Push::ChangedFile::DELETION,
        previous_path: "previous_path.txt"
      )

      assert file.deletion?
      assert_nil file.previous_path
      assert_equal "previous_path.txt", file.path
      assert_equal "D", file.change_type
    end

    test "renaming" do
      file = Repositories::Push::ChangedFile.new(
        change_type: Repositories::Push::ChangedFile::RENAMING,
        path: "path.txt",
        previous_path: "previous_path.txt",
        score: 50
      )

      assert file.renaming?
      assert_equal "R050", file.change_type
      assert_equal "path.txt", file.path
      assert_equal "previous_path.txt", file.previous_path
    end

    test "modifying" do
      file = Repositories::Push::ChangedFile.new(
        change_type: Repositories::Push::ChangedFile::MODIFYING,
        path: "path.txt",
        previous_path: "previous_path.txt",
        score: 50
      )
    end

    test "type change_type" do
      file = Repositories::Push::ChangedFile.new(
        change_type: Repositories::Push::ChangedFile::TYPE,
        path: "path.txt",
        previous_path: "previous_path.txt",
        score: 50
      )

      assert file.type?
      assert_nil file.previous_path
    end

    test "unknown change type" do
      file = Repositories::Push::ChangedFile.new(
        change_type: Repositories::Push::ChangedFile::UNKNOWN,
        path: "path.txt",
        previous_path: "previous_path.txt",
        score: 50
      )

      assert_equal Repositories::Push::ChangedFile::UNKNOWN, file.change_type
    end

    test "unsupported change_type values default to U" do
      file = Repositories::Push::ChangedFile.new(change_type: "Z")

      assert_equal Repositories::Push::ChangedFile::UNKNOWN, file.change_type
    end
  end

  test "it is big? if is one of the big types" do
    file = Repositories::Push::ChangedFile.new(
      change_type: Repositories::Push::ChangedFile::ADDITION,
      path: "test.#{Repositories::Push::ChangedFile::BigExtensions.first}",
      oid: SecureRandom.hex(32)
    )

    assert file.big?
  end

  context "escaping paths" do
    test "simple" do
      assert_equal "", quote_path("")
      assert_equal "a", quote_path("a")
      assert_equal "a/b", quote_path("a/b")
    end

    test "spaces" do
      assert_equal "a b", quote_path("a b")
      assert_equal " a b c d ", quote_path(" a b c d ")
    end

    test "quotes" do
      assert_equal '"\"quoted\""', quote_path('"quoted"')
      assert_equal "'quoted'", quote_path("'quoted'")
    end

    test "020" do
      assert_equal %Q{"blah/\\020blah\\020/blah"}, quote_path("blah/\x10blah\x10/blah")
    end

    test "kitchen sink" do
      tests = [
        [0x00, %Q{"\\000\\001\\002\\003\\004\\005\\006\\a\\b\\t\\n\\v\\f\\r\\016\\017"}],
        [0x10, %Q{"\\020\\021\\022\\023\\024\\025\\026\\027\\030\\031\\032\\033\\034\\035\\036\\037"}],
        [0x20, %Q{" !\\"\#$%&'()*+,-./"}],
        [0x30, %Q{0123456789:;<=>?}],
        [0x40, %Q{@ABCDEFGHIJKLMNO}],
        [0x50, %Q{"PQRSTUVWXYZ[\\\\]^_"}],
        [0x60, %Q{`abcdefghijklmno}],
        [0x70, %Q{"pqrstuvwxyz{|}~\\177"}],
        [0x80, %Q{"\\200\\201\\202\\203\\204\\205\\206\\207\\210\\211\\212\\213\\214\\215\\216\\217"}],
        # assume these all work if 0x80 and 0xF0 do.
        [0xF0, %Q{"\\360\\361\\362\\363\\364\\365\\366\\367\\370\\371\\372\\373\\374\\375\\376\\377"}],
      ]
      tests.each do |prefix, expected|
        s = (0..15).map { |second| prefix + second }.map(&:chr).join
        assert_equal expected, quote_path(s)
      end
    end
  end

  def quote_path(path)
    Repositories::Push::ChangedFile.new(path: path.b).path
  end
end
