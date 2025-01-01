# typed: strict
# frozen_string_literal: true

require "test_helper"

class SyntaxHighlightedDiffTest < GitHub::TestCase
  setup do
    Spokesd.enable_spokesd

    reset_cache
    enable_cache_storage(/colorized_lines:/)
  end

  teardown do
    disable_cache_storage
  end

  context "highlight!" do
    test "does not raise exception for diffs containing renames" do
      parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/coreos-base/update_engine/update_engine-0.0.1-r397.ebuild b/coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
similarity index 100%
rename from coreos-base/update_engine/update_engine-0.0.1-r397.ebuild
rename to coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
diff --git a/coreos-base/update_engine/update_engine-9999.ebuild b/coreos-base/update_engine/update_engine-9999.ebuild
index edfdf097b7e40afc2303bf601e314256b3fffa0c..ef56da4bd660b3abe55858c497dc6f323fc5bc0e 100644
--- a/coreos-base/update_engine/update_engine-9999.ebuild
+++ b/coreos-base/update_engine/update_engine-9999.ebuild
@@ -8,7 +8,7 @@ CROS_WORKON_REPO="git://github.com"
 if [[ "${PV}" == 9999 ]]; then
 	KEYWORDS="~amd64 ~arm ~x86"
 else
-	CROS_WORKON_COMMIT="bdf691f03fa90b04afc67dfc0a5a0b802c353582"
+	CROS_WORKON_COMMIT="641533738ad1b21e52fb70a20c4b48050157495c"
 	KEYWORDS="amd64 arm x86"
 fi

      EOS

      entries = []
      parser.each { |entry| entries << entry }

      assert_nothing_raised do
        SyntaxHighlightedDiff.new(create :repository).highlight!(entries)
      end
    end

    test "does not raise exception for diffs containing added/removed files" do
      parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/.gitmodules b/.gitmodules
deleted file mode 100644
index d32caf7099db3ec1a161b510b10744cd4dfaf423..0000000000000000000000000000000000000000
--- a/.gitmodules
+++ /dev/null
@@ -1,3 +0,0 @@
-[submodule "pepto-symbol"]
-	path = pepto-symbol
-	url = https://github.com/aroben/pepto-symbol
diff --git a/pepto-symbol b/pepto-symbol
deleted file mode 160000
index e8d04500325fcb40cff2c7540e6be62dc3997182..0000000000000000000000000000000000000000
--- a/pepto-symbol
+++ /dev/null
@@ -1 +0,0 @@
-Subproject commit e8d04500325fcb40cff2c7540e6be62dc3997182
diff --git a/pepto-symbol b/pepto-symbol
new file mode 100644
index 0000000000000000000000000000000000000000..bc297861b0232823640754e305fcbc85298255fd
--- /dev/null
+++ b/pepto-symbol
@@ -0,0 +1 @@
+Subproject commit e8d04500325fcb40cff2c7540e6be62dc3997182 haha!
      EOS

      entries = []
      parser.each { |entry| entries << entry }

      assert_nothing_raised do
        SyntaxHighlightedDiff.new(create :repository).highlight!(entries)
      end
    end

    test "does not highlight binary files" do
      repo = create(:repository, from_example: :raw_blobs)
      # This commit touches one file, and that file is binary (a PNG).
      commit = repo.commits.find("55b141a4d58ba863c35e0d2f4af84a98cc950872")

      GitRPC::Client.any_instance.stubs(:read_blobs).raises(RuntimeError.new("should not have called #read_blobs"))
      TreeEntry.any_instance.stubs(:colorized_lines).raises(RuntimeError.new("should not have called #colorized_lines"))

      assert_nothing_raised do
        SyntaxHighlightedDiff.new(repo).highlight!(commit.diff.entries)
      end
    end

    test "does not highlight renamed files" do
      parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/coreos-base/update_engine/update_engine-0.0.1-r397.ebuild b/coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
similarity index 100%
rename from coreos-base/update_engine/update_engine-0.0.1-r397.ebuild
rename to coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
      EOS

      entries = []
      parser.each { |entry| entries << entry }

      GitRPC::Client.any_instance.stubs(:read_blobs).raises(RuntimeError.new("should not have called #read_blobs"))
      TreeEntry.any_instance.stubs(:colorized_lines).raises(RuntimeError.new("should not have called #colorized_lines"))

      assert_nothing_raised do
        SyntaxHighlightedDiff.new(create :repository).highlight!(entries)
      end
    end

    test "does not highlight files for truncated diffs" do
      parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/coreos-base/update_engine/update_engine-9999.ebuild b/coreos-base/update_engine/update_engine-9999.ebuild
index edfdf097b7e40afc2303bf601e314256b3fffa0c..ef56da4bd660b3abe55858c497dc6f323fc5bc0e 100644
--- a/coreos-base/update_engine/update_engine-9999.ebuild
+++ b/coreos-base/update_engine/update_engine-9999.ebuild
Truncating diff: it is too big to display
      EOS

      entries = []
      parser.each { |entry| entries << entry }

      GitRPC::Client.any_instance.stubs(:read_blobs).raises(RuntimeError.new("should not have called #read_blobs"))
      TreeEntry.any_instance.stubs(:colorized_lines).raises(RuntimeError.new("should not have called #colorized_lines"))

      assert_nothing_raised do
        SyntaxHighlightedDiff.new(create :repository).highlight!(entries)
      end
    end

    test "highlights 50 entries at a time" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")
      diff = SyntaxHighlightedDiff.new(repo)

      diff.highlight!(commit.diff.entries)

      # The first 50 entries should be highlighted.
      commit.diff.entries.each_with_index.take(50).each do |entry, index|
        refute_nil diff.colorized_lines(entry), "#{index}: #{entry.path} was not highlighted"
      end

      # Entries after the 50th should not be highlighted.
      commit.diff.entries.each_with_index.drop(50).each do |entry, index|
        assert_nil diff.colorized_lines(entry), "#{index}: #{entry.path} was highlighted"
      end

      # Highlighting again should highlight another 50 entries.
      diff.highlight!(commit.diff.entries)

      commit.diff.entries.each_with_index.drop(50).take(50).each do |entry, index|
        refute_nil diff.colorized_lines(entry), "#{index}: #{entry.path} was not highlighted"
      end
      commit.diff.entries.each_with_index.drop(100).each do |entry, index|
        assert_nil diff.colorized_lines(entry), "#{index}: #{entry.path} was highlighted"
      end
    end

    test "skips over plaintext entries" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")
      diff = SyntaxHighlightedDiff.new(repo)

      # This diff contains:
      #   100 .rb files
      #   100 .txt files
      #   100 .rb files
      # …in that order.

      # Highlight the first set of .rb files.
      diff.highlight!(commit.diff.entries)
      diff.highlight!(commit.diff.entries)

      # At this point the 100th file should be highlighted.
      refute_nil diff.colorized_lines(commit.diff.entries[99])
      # But not the 201st file (i.e., the first .rb file after the .txt files).
      assert_nil diff.colorized_lines(commit.diff.entries[200])

      # Call #highlight! twice more to move past the .txt files.
      diff.highlight!(commit.diff.entries)
      diff.highlight!(commit.diff.entries)

      # The 201st file (i.e., the first .rb file after the .txt files) still hasn't gotten highlighted.
      assert_nil diff.colorized_lines(commit.diff.entries[200])

      # Highlight once more to highlight the first 50 .rb files in the second set.
      diff.highlight!(commit.diff.entries)

      commit.diff.entries.each_with_index.drop(200).take(50).each do |entry, index|
        refute_nil diff.colorized_lines(entry), "#{index}: #{entry.path} was not highlighted"
      end
    end

    test "highlights entries when blobs are already highlighted" do
      repo = create(:repository, from_example: :mojombo_grit)

      commit = repo.commits.find("4c596908ce1136e8c32174ba13892c6fe68a010d")

      head_blob = repo.tree_entry(commit.oid, "lib/grit/commit.rb")
      base_blob = repo.tree_entry(commit.parent_oids.first, "lib/grit/commit.rb")

      # Highlight both the blobs.
      head_blob.colorized_lines
      base_blob.colorized_lines

      entry = commit.diff.entries.find { |e| e.path == "lib/grit/commit.rb" }

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])

      refute_nil diff.colorized_lines(entry)
    end

    test "highlights entries of present empty files which become non-empty" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("fe0bdd089dee870a8958bd716348c3ea6b807b47")
      entry = commit.diff.entries.find { |e| e.path == "initial-empty.html" }

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])
      colorized_lines = diff.colorized_lines(entry)

      refute_nil colorized_lines
      assert_equal 2, T.must(colorized_lines).length
    end

    test "highlights entries of present non-empty files which become empty" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("6e77d7857121e71bcc8fac1681b6350d0c721d36")
      entry = commit.diff.entries.find { |e| e.path == "finally-empty.html" }

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])
      colorized_lines = diff.colorized_lines(entry)

      refute_nil colorized_lines
      assert_equal 2, T.must(colorized_lines).length
    end

    test "does not highlight entries of previously highlightable files which become non-highlightable" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("402b679bd56e1b9ebfd877f0181e8bde3799e9cc")
      entry = commit.diff.entries.find { |e| e.path == "initial-ruby.txt" }

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])
      colorized_lines = diff.colorized_lines(entry)

      refute_nil colorized_lines
      assert_equal 9, T.must(colorized_lines).length
    end

    test "does not highlight unhighlightable entries" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")
      entry = commit.diff.entries.find { |e| e.path.end_with?(".txt") }
      diff = SyntaxHighlightedDiff.new(repo)

      TreeEntry.any_instance.stubs(:colorized_lines!).raises(RuntimeError.new("should not have called #colorized_lines!"))

      assert_nothing_raised do
        diff.highlight!([entry])
      end
    end

    test "does not highlight entries with unknown file types" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("0dc62906f06fde259faf7fd9d4245dad83ba78a8")

      assert_nil repo.tree_entry(commit.oid, "unknown.thisisnotafileextension").language

      entry = commit.diff.entries.first
      assert_equal "unknown.thisisnotafileextension", entry.path
      diff = SyntaxHighlightedDiff.new(repo)

      TreeEntry.any_instance.stubs(:colorized_lines!).raises(RuntimeError.new("should not have called #colorized_lines!"))

      assert_nothing_raised do
        diff.highlight!([entry])
      end
    end

    test "does not highlight entries with invalid tm_scopes" do
      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("9e52981ad9e2c7ad02be4b9fa83672ba93c318b5")

      refute GitHub::Colorize.valid_scope?(repo.tree_entry(commit.oid, "hello.txt").language.tm_scope), "Someone added a grammar for Text files so this test is no longer valid"

      entry = commit.diff.entries.first
      assert_equal "hello.txt", entry.path
      diff = SyntaxHighlightedDiff.new(repo)

      TreeEntry.any_instance.stubs(:colorized_lines!).raises(RuntimeError.new("should not have called #colorized_lines!"))

      assert_nothing_raised do
        diff.highlight!([entry])
      end
    end

    test "does not blow up when the cache returns nil values" do
      # simulates a cache failover (see GitHub::Cache::Failover)

      repo = create(:repository, from_example: :syntax_highlighted_diffs)
      commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")

      entry = commit.diff.entries.find { |e| e.path == "a001.rb" }
      diff = SyntaxHighlightedDiff.new(repo)

      GitHub.cache.stubs(:get).returns(nil)
      diff.highlight!([entry])

      assert_nil diff.colorized_lines(entry)
    end
  end

  context "colorized_lines" do
    test "returns nil when no highlighted data is availble" do
      repo = create(:repository, from_example: :mojombo_grit)
      commit = repo.commits.find("5f141d9c0181b8732c0ec2fab4967f0ffa24fa3f")
      entry = commit.diff.entries.first

      assert_nil SyntaxHighlightedDiff.new(repo).colorized_lines(entry)
    end

    test "returns colorized lines" do
      repo = create(:repository, from_example: :mojombo_grit)
      commit = repo.commits.find("5f141d9c0181b8732c0ec2fab4967f0ffa24fa3f")
      entry = commit.diff.entries.first

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])
      lines = diff.colorized_lines(entry)

      assert_equal 25, entry.lines.length
      assert_equal 25, T.must(lines).length
      assert_includes T.must(lines)[1], "<span class="
      T.must(lines).each do |line|
        if line
          assert_predicate line, :html_safe?
        end
      end
      # nonewline placeholder
      assert_nil T.must(lines)[25]
    end

    test "does not blow up on new empty files" do
      repo = create(:repository, from_example: :commit_api)
      # This commit adds a file that is empty.
      commit = repo.commits.find("4cc5c34aac21592b20c873f53647238ac370293f")
      entry = commit.diff.entries.first
      assert_nil entry.text

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])
      assert_nil diff.colorized_lines(entry)
    end

    test "does not blow up on added files" do
      repo = create(:repository, from_example: :mojombo_grit)
      commit = repo.commits.find("46291865ba0f6e0c9818b11be799fe2db6964d56")
      entry = commit.diff.entries.find { |e| e.path == "lib/grit/diff.rb" }
      assert_predicate entry, :added?

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])

      refute_nil diff.colorized_lines(entry)
    end

    test "does not blow up on removed files" do
      repo = create(:repository, from_example: :mojombo_grit)
      commit = repo.commits.find("d01a4cfad6ea50285c4710243e3cbe019d381eba")
      entry = commit.diff.entries.find { |e| e.path == "lib/grit/grit.rb" }
      assert_predicate entry, :deleted?

      diff = SyntaxHighlightedDiff.new(repo)
      diff.highlight!([entry])

      refute_nil diff.colorized_lines(entry)
    end

    test "does not return a previously-cached value for a different set of injected context lines" do
      repo = create(:repository, from_example: :mojombo_grit)

      diff = GitHub::Diff.new(repo, "5f141d9c0181b8732c0ec2fab4967f0ffa24fa3f", nil, {
        context_lines: {
          "lib/grit/repo.rb" => [1..1],
        },
      })
      entry = diff.entries.first
      highlighted = SyntaxHighlightedDiff.new(repo)
      highlighted.highlight!([entry])
      lines_a = highlighted.colorized_lines(entry)

      diff = GitHub::Diff.new(repo, "5f141d9c0181b8732c0ec2fab4967f0ffa24fa3f", nil, {
        context_lines: {
          "lib/grit/repo.rb" => [5..5], # Same diff, different injected context lines
        },
      })
      entry = diff.entries.first
      highlighted = SyntaxHighlightedDiff.new(repo)
      highlighted.highlight!([entry])
      lines_b = highlighted.colorized_lines(entry)

      refute_equal lines_a, lines_b
    end
  end
end

class StyledDirectiveSyntaxHighlightedDiffTest < GitHub::TestCase
  setup do
    Spokesd.enable_spokesd

    reset_cache
    enable_cache_storage(/styling_directives:/)
  end

  teardown do
    disable_cache_storage
  end

  test "does not raise exception for diffs containing renames" do
    parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/coreos-base/update_engine/update_engine-0.0.1-r397.ebuild b/coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
similarity index 100%
rename from coreos-base/update_engine/update_engine-0.0.1-r397.ebuild
rename to coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
diff --git a/coreos-base/update_engine/update_engine-9999.ebuild b/coreos-base/update_engine/update_engine-9999.ebuild
index edfdf097b7e40afc2303bf601e314256b3fffa0c..ef56da4bd660b3abe55858c497dc6f323fc5bc0e 100644
--- a/coreos-base/update_engine/update_engine-9999.ebuild
+++ b/coreos-base/update_engine/update_engine-9999.ebuild
@@ -8,7 +8,7 @@ CROS_WORKON_REPO="git://github.com"
 if [[ "${PV}" == 9999 ]]; then
  KEYWORDS="~amd64 ~arm ~x86"
 else
-	CROS_WORKON_COMMIT="bdf691f03fa90b04afc67dfc0a5a0b802c353582"
+	CROS_WORKON_COMMIT="641533738ad1b21e52fb70a20c4b48050157495c"
  KEYWORDS="amd64 arm x86"
 fi

    EOS

    entries = []
    parser.each { |entry| entries << entry }

    assert_nothing_raised do
      SyntaxHighlightedDiff.new(create :repository).highlight_with_styled_directives!(entries)
    end
  end

  test "does not raise exception for diffs containing added/removed files" do
    parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/.gitmodules b/.gitmodules
deleted file mode 100644
index d32caf7099db3ec1a161b510b10744cd4dfaf423..0000000000000000000000000000000000000000
--- a/.gitmodules
+++ /dev/null
@@ -1,3 +0,0 @@
-[submodule "pepto-symbol"]
-	path = pepto-symbol
-	url = https://github.com/aroben/pepto-symbol
diff --git a/pepto-symbol b/pepto-symbol
deleted file mode 160000
index e8d04500325fcb40cff2c7540e6be62dc3997182..0000000000000000000000000000000000000000
--- a/pepto-symbol
+++ /dev/null
@@ -1 +0,0 @@
-Subproject commit e8d04500325fcb40cff2c7540e6be62dc3997182
diff --git a/pepto-symbol b/pepto-symbol
new file mode 100644
index 0000000000000000000000000000000000000000..bc297861b0232823640754e305fcbc85298255fd
--- /dev/null
+++ b/pepto-symbol
@@ -0,0 +1 @@
+Subproject commit e8d04500325fcb40cff2c7540e6be62dc3997182 haha!
    EOS

    entries = []
    parser.each { |entry| entries << entry }

    assert_nothing_raised do
      SyntaxHighlightedDiff.new(create :repository).highlight_with_styled_directives!(entries)
    end
  end

  test "does not highlight binary files" do
    repo = create(:repository, from_example: :raw_blobs)
    # This commit touches one file, and that file is binary (a PNG).
    commit = repo.commits.find("55b141a4d58ba863c35e0d2f4af84a98cc950872")

    GitRPC::Client.any_instance.stubs(:read_blobs).raises(RuntimeError.new("should not have called #read_blobs"))
    TreeEntry.any_instance.stubs(:styling_directives).raises(RuntimeError.new("should not have called #styling_directives"))

    assert_nothing_raised do
      SyntaxHighlightedDiff.new(repo).highlight_with_styled_directives!(commit.diff.entries)
    end
  end

  test "does not highlight renamed files" do
    parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/coreos-base/update_engine/update_engine-0.0.1-r397.ebuild b/coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
similarity index 100%
rename from coreos-base/update_engine/update_engine-0.0.1-r397.ebuild
rename to coreos-base/update_engine/update_engine-0.0.1-r398.ebuild
    EOS

    entries = []
    parser.each { |entry| entries << entry }

    GitRPC::Client.any_instance.stubs(:read_blobs).raises(RuntimeError.new("should not have called #read_blobs"))
    TreeEntry.any_instance.stubs(:styling_directives).raises(RuntimeError.new("should not have called #styling_directives"))

    assert_nothing_raised do
      SyntaxHighlightedDiff.new(create :repository).highlight_with_styled_directives!(entries)
    end
  end

  test "does not highlight files for truncated diffs" do
    parser = GitHub::Diff::Parser.new(<<-EOS)
diff --git a/coreos-base/update_engine/update_engine-9999.ebuild b/coreos-base/update_engine/update_engine-9999.ebuild
index edfdf097b7e40afc2303bf601e314256b3fffa0c..ef56da4bd660b3abe55858c497dc6f323fc5bc0e 100644
--- a/coreos-base/update_engine/update_engine-9999.ebuild
+++ b/coreos-base/update_engine/update_engine-9999.ebuild
Truncating diff: it is too big to display
    EOS

    entries = []
    parser.each { |entry| entries << entry }

    GitRPC::Client.any_instance.stubs(:read_blobs).raises(RuntimeError.new("should not have called #read_blobs"))
    TreeEntry.any_instance.stubs(:styling_directives).raises(RuntimeError.new("should not have called #styling_directives"))

    assert_nothing_raised do
      SyntaxHighlightedDiff.new(create :repository).highlight_with_styled_directives!(entries)
    end
  end

  test "highlights 50 entries at a time" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")
    diff = SyntaxHighlightedDiff.new(repo)

    diff.highlight_with_styled_directives!(commit.diff.entries)

    # The first 50 entries should be highlighted.
    commit.diff.entries.each_with_index.take(50).each do |entry, index|
      refute_nil diff.styling_directive(entry), "#{index}: #{entry.path} was not highlighted"
    end

    # Entries after the 50th should not be highlighted.
    commit.diff.entries.each_with_index.drop(50).each do |entry, index|
      assert_nil diff.styling_directive(entry), "#{index}: #{entry.path} was highlighted"
    end

    # Highlighting again should highlight another 50 entries.
    diff.highlight_with_styled_directives!(commit.diff.entries)

    commit.diff.entries.each_with_index.drop(50).take(50).each do |entry, index|
      refute_nil diff.styling_directive(entry), "#{index}: #{entry.path} was not highlighted"
    end

    commit.diff.entries.each_with_index.drop(100).each do |entry, index|
      assert_nil diff.styling_directive(entry), "#{index}: #{entry.path} was highlighted"
    end
  end

  test "skips over plaintext entries" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")
    diff = SyntaxHighlightedDiff.new(repo)

    # This diff contains:
    #   100 .rb files
    #   100 .txt files
    #   100 .rb files
    # …in that order.

    # Highlight the first set of .rb files.
    diff.highlight_with_styled_directives!(commit.diff.entries)
    diff.highlight_with_styled_directives!(commit.diff.entries)

    # At this point the 100th file should be highlighted.
    refute_nil diff.styling_directive(commit.diff.entries[99])
    # But not the 201st file (i.e., the first .rb file after the .txt files).
    assert_nil diff.styling_directive(commit.diff.entries[200])

    # Call #highlight_with_styled_directives! twice more to move past the .txt files.
    diff.highlight_with_styled_directives!(commit.diff.entries)
    diff.highlight_with_styled_directives!(commit.diff.entries)

    # The 201st file (i.e., the first .rb file after the .txt files) still hasn't gotten highlighted.
    assert_nil diff.styling_directive(commit.diff.entries[200])

    # Highlight once more to highlight the first 50 .rb files in the second set.
    diff.highlight_with_styled_directives!(commit.diff.entries)

    commit.diff.entries.each_with_index.drop(200).take(50).each do |entry, index|
      refute_nil diff.styling_directive(entry), "#{index}: #{entry.path} was not highlighted"
    end
  end

  test "highlights entries when blobs are already highlighted" do
    repo = create(:repository, from_example: :mojombo_grit)

    commit = repo.commits.find("4c596908ce1136e8c32174ba13892c6fe68a010d")

    head_blob = repo.tree_entry(commit.oid, "lib/grit/commit.rb")
    base_blob = repo.tree_entry(commit.parent_oids.first, "lib/grit/commit.rb")

    # Highlight both the blobs.
    head_blob.styling_directives
    base_blob.styling_directives

    entry = commit.diff.entries.find { |e| e.path == "lib/grit/commit.rb" }

    diff = SyntaxHighlightedDiff.new(repo)
    diff.highlight_with_styled_directives!([entry])

    refute_nil diff.styling_directive(entry)
  end

  test "highlights entries of present empty files which become non-empty" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("fe0bdd089dee870a8958bd716348c3ea6b807b47")
    entry = commit.diff.entries.find { |e| e.path == "initial-empty.html" }

    diff = SyntaxHighlightedDiff.new(repo)
    diff.highlight_with_styled_directives!([entry])
    styling_directives = diff.styling_directive(entry)

    refute_nil styling_directives
    assert_equal 2, styling_directives.length
  end

  test "highlights entries of present non-empty files which become empty" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("6e77d7857121e71bcc8fac1681b6350d0c721d36")
    entry = commit.diff.entries.find { |e| e.path == "finally-empty.html" }

    diff = SyntaxHighlightedDiff.new(repo)
    diff.highlight_with_styled_directives!([entry])
    styling_directives = diff.styling_directive(entry)

    refute_nil styling_directives
    assert_equal 2, styling_directives.length
  end

  test "does not highlight entries of previously highlightable files which become non-highlightable" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("402b679bd56e1b9ebfd877f0181e8bde3799e9cc")
    entry = commit.diff.entries.find { |e| e.path == "initial-ruby.txt" }

    diff = SyntaxHighlightedDiff.new(repo)
    diff.highlight_with_styled_directives!([entry])
    styling_directives = diff.styling_directive(entry)

    refute_nil styling_directives
    assert_equal 9, styling_directives.length
  end

  test "does not highlight unhighlightable entries" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")
    entry = commit.diff.entries.find { |e| e.path.end_with?(".txt") }
    diff = SyntaxHighlightedDiff.new(repo)

    TreeEntry.any_instance.stubs(:styling_directives!).raises(RuntimeError.new("should not have called #styling_directives!"))

    assert_nothing_raised do
      diff.highlight_with_styled_directives!([entry])
    end
  end

  test "does not highlight entries with unknown file types" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("0dc62906f06fde259faf7fd9d4245dad83ba78a8")

    assert_nil repo.tree_entry(commit.oid, "unknown.thisisnotafileextension").language

    entry = commit.diff.entries.first
    assert_equal "unknown.thisisnotafileextension", entry.path
    diff = SyntaxHighlightedDiff.new(repo)

    TreeEntry.any_instance.stubs(:styling_directives!).raises(RuntimeError.new("should not have called #styling_directives!"))
    assert_nothing_raised do
      diff.highlight_with_styled_directives!([entry])
    end
  end

  test "does not highlight entries with invalid tm_scopes" do
    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("9e52981ad9e2c7ad02be4b9fa83672ba93c318b5")

    refute GitHub::Colorize.valid_scope?(repo.tree_entry(commit.oid, "hello.txt").language.tm_scope), "Someone added a grammar for Text files so this test is no longer valid"

    entry = commit.diff.entries.first
    assert_equal "hello.txt", entry.path
    diff = SyntaxHighlightedDiff.new(repo)

    TreeEntry.any_instance.stubs(:styling_directives!).raises(RuntimeError.new("should not have called #styling_directives!"))

    assert_nothing_raised do
      diff.highlight_with_styled_directives!([entry])
    end
  end

  test "does not blow up when the cache returns nil values" do
    # simulates a cache failover (see GitHub::Cache::Failover)

    repo = create(:repository, from_example: :syntax_highlighted_diffs)
    commit = repo.commits.find("1528f717fe6e89c4f203e0e0e3d588f7d0a27c97")

    entry = commit.diff.entries.find { |e| e.path == "a001.rb" }
    diff = SyntaxHighlightedDiff.new(repo)

    GitHub.cache.stubs(:get).returns(nil)
    diff.highlight_with_styled_directives!([entry])

    assert_nil diff.styling_directive(entry)
  end
end
