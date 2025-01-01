# typed: true
# frozen_string_literal: true

require "test_helper"

class TreeEntryTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    # feature flag business
    @github = create(:organization, login: "github")

    @git_lfs_repo = create :private_repository, owner: @github
    @git_lfs_commit = "a37b01ed79cac5bf718c3a5649955dae7f43268a"
    @git_lfs_images_tree = "2b33e1a9c8f114dcd5f8e2df2f4b21b531d819d7"
    @git_lfs_oid = "e9634919a7ce5e696812e13648c764c6ef557cddfd9c0dcce9ac7cc3d55193e0"
    @git_lfs_blob = Media::Blob.upload(@git_lfs_repo, @git_lfs_oid,
      size: 1, pusher: @github)

    @repo = create(:repository)

    GitHub.config.enable("git-lfs", @github.members.first)
  end

  setup do
    example_repo :git_lfs, @git_lfs_repo
    example_repo :simple, @repo
  end

  # feature flag business
  teardown do
    GitHub::FeatureFlag.team_cache.clear
  end

  context "#executable?" do
    test "true when executable for user" do
      tree_entry = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
      TreeEntry.any_instance.stubs(:mode).returns("100744")
      assert_predicate tree_entry, :executable?
    end

    test "true when executable for group" do
      tree_entry = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
      TreeEntry.any_instance.stubs(:mode).returns("100614")
      assert_predicate tree_entry, :executable?
    end

    test "true when executable for other" do
      tree_entry = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
      TreeEntry.any_instance.stubs(:mode).returns("100625")
      assert_predicate tree_entry, :executable?
    end

    test "false when not executable for user, group, or other" do
      tree_entry = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
      TreeEntry.any_instance.stubs(:mode).returns("100644")
      refute_predicate tree_entry, :executable?
    end
  end

  test "gets size for tree entries if asked" do
    [true, false].each do |skip_size|
      _, entries = @git_lfs_repo.tree_entries(@git_lfs_commit, "", skip_size: skip_size)
      assert_equal 2, entries.size, entries.inspect
      hash = entries.index_by(&:name)
      assert_equal skip_size ? 0 : 176, hash[".gitattributes"].size
      assert hash[".gitattributes"].from_collection?
      assert_equal 0, hash["images"].size
      assert hash["images"].from_collection?

      _, entries = @git_lfs_repo.tree_entries(@git_lfs_commit, "images", skip_size: skip_size)
      hash = entries.index_by(&:name)
      assert_equal 2, entries.size
      assert_equal skip_size ? 0 : 77, hash["taco.jpg"].size
      assert hash["taco.jpg"].from_collection?
      assert_equal skip_size ? 0 : 117, hash["taco-v2.jpg"].size
      assert hash["taco-v2.jpg"].from_collection?
    end
  end

  test "gets size for git blob" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, ".gitattributes")
    assert_equal 176, tree.size
    assert_equal 176, tree.object_size
    refute tree.from_collection?
  end

  test "gets size for git lfs blob with legacy pointer" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
    assert_equal 1, tree.size # size from git lfs blob record
    assert_equal 77, tree.object_size
    refute tree.from_collection?
  end

  test "gets size for git lfs blob with git media v2 pointer" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg")
    assert_equal 123, tree.size # size from pointer metadata
    assert_equal 117, tree.object_size
    refute tree.from_collection?
  end

  test "small git lfs blobs are not viewable" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg")
    refute tree.large?
    refute tree.viewable?
    refute tree.text?
  end

  test "large git lfs blobs are not viewable" do
    @git_lfs_blob.update! size: 5.megabytes
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
    assert tree.large?
    refute tree.viewable?
    refute tree.text?
  end

  test "checks git_lfs?" do
    assert @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg").git_lfs?
    assert @git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg").git_lfs?
  end

  test "gets git_lfs_blob with legacy pointer" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
    assert_equal "blob", tree.type
    assert_equal "76c060a5b5a4fb4cc079bb1fb171fd69066fd858", tree.oid
    assert_equal @git_lfs_blob, tree.git_lfs_blob
  end

  test "gets git_lfs_blob with v2 pointer" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg")
    assert_equal "blob", tree.type
    assert_equal "486894c49b8fb40145dab46290af18c1583fa2ba", tree.oid
    assert_equal @git_lfs_blob, tree.git_lfs_blob
  end

  test "gets git_lfs_oid with legacy pointer" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg")
    assert_equal "blob", tree.type
    assert_equal "76c060a5b5a4fb4cc079bb1fb171fd69066fd858", tree.oid
    assert_equal @git_lfs_oid, tree.git_lfs_oid
  end

  test "gets git_lfs_oid with v2 pointer" do
    tree = @git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg")
    assert_equal "blob", tree.type
    assert_equal "486894c49b8fb40145dab46290af18c1583fa2ba", tree.oid
    assert_equal @git_lfs_oid, tree.git_lfs_oid
  end

  test "git_lfs? requires Media::Blob" do
    Media::Blob.delete_all
    assert !@git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg").git_lfs?
    assert !@git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg").git_lfs?
  end

  test "git_lfs? requires feature flag" do
    staff = create(:staff_admin_user)
    @github.disable_git_lfs staff
    begin
      assert !@git_lfs_repo.blob(@git_lfs_commit, "images/taco.jpg").git_lfs?
      assert !@git_lfs_repo.blob(@git_lfs_commit, "images/taco-v2.jpg").git_lfs?
    ensure
      @github.enable_git_lfs staff
    end
  end

  test "equality" do
    oid  = @repo.heads.find("master").target_oid
    blob = @repo.blob(oid, "a")

    assert blob
    assert_equal blob, blob.dup

    assert_equal blob, @repo.blob(oid, "a")
  end

  test "line count" do
    oid  = @repo.heads.find("master").target_oid
    blob = @repo.blob(oid, "a")

    assert_equal 3, blob.lines.count
  end

  test "line count with carriage returns" do
    oid  = @repo.heads.find("cr-line-endings").target_oid
    blob = @repo.blob(oid, "a")

    assert_equal 3, blob.lines.count
  end

  test "path does not prepend an unset path_prefix" do
    _, entries = @git_lfs_repo.tree_entries(@git_lfs_images_tree, "")
    entry = entries.find { |e| e.name == "taco.jpg" }

    assert_equal "taco.jpg", entry.path
  end

  test "path does not prepend a nil path_prefix" do
    _, entries = @git_lfs_repo.tree_entries(@git_lfs_images_tree, "")
    entry = entries.find { |e| e.name == "taco.jpg" }
    entry.path_prefix = nil

    assert_equal "taco.jpg", entry.path
  end

  test "path does not prepend an empty path_prefix" do
    _, entries = @git_lfs_repo.tree_entries(@git_lfs_images_tree, "")
    entry = entries.find { |e| e.name == "taco.jpg" }
    entry.path_prefix = ""

    assert_equal "taco.jpg", entry.path
  end

  test "path prepends a path_prefix" do
    _, entries = @git_lfs_repo.tree_entries(@git_lfs_images_tree, "")
    entry = entries.find { |e| e.name == "taco.jpg" }
    entry.path_prefix = "soft"

    assert_equal "soft/taco.jpg", entry.path
  end

  context "async_colorized_lines" do
    test "returns an array of colorized lines" do
      content = <<-EOF
        <h2>Projects</h2>
        <p>There are many exciting (new) <a href="projects/index.html">projects</a> that you can contribute to:</p>
      EOF
      blob = blob(name: "test.html", content: content)
      blob.stubs(:tm_scope).returns(nil)
      assert blob.async_colorized_lines.sync.first.include?("<span class")
      assert blob.async_file_lines.sync.first[:html].include?("<span class")
      assert_equal 1, blob.async_file_lines.sync.first[:number]
    end
  end

  context "colorized_lines" do

    context "colorization strategy" do
      test "default - nil" do
        blob = blob(name: "test.rb", content: "def foo(bar)\n\"baz\"", truncated: true)

        assert_equal blob.colorized_lines, ["<span class='source.ruby'>def foo(bar)</span>"]
      end

      test ":from_cache_only returns nil if there is no cache" do
        blob = blob(name: "test.rb", content: "def foo(bar)\n\"baz\"", truncated: true)

        assert_nil blob.colorized_lines(strategy: :from_cache_only)

        # Populate cache
        blob.colorized_lines
        assert_equal blob.colorized_lines(strategy: :from_cache_only), ["<span class='source.ruby'>def foo(bar)</span>"]
      end

      test ":from_cache_or_plain returns plain text if there is no cache" do
        blob = blob(name: "test.rb", content: "def foo(bar)\n\"baz\"", truncated: true)

        assert_equal blob.colorized_lines(strategy: :from_cache_or_plain), ["def foo(bar)", "&quot;baz&quot;"]

        # Populate cache
        blob.colorized_lines
        assert_equal blob.colorized_lines(strategy: :from_cache_or_plain), ["<span class='source.ruby'>def foo(bar)</span>"]
      end
    end

    test "truncated blob trims off last incomplete line" do
      blob = blob(name: "test.rb", content: "def foo(bar)\n\"baz\"", truncated: true)

      last_line = blob.colorized_lines.last
      refute last_line.include?("baz"), "last line shouldn't have included \"baz\", but was: #{last_line}"
    end

    test "truncated blob doesn't trim off last complete line" do
      blob = blob(name: "test.rb", content: "def foo(bar)\n\"baz\"\n", truncated: true)

      last_line = blob.colorized_lines.last
      assert last_line.include?("baz"), "last line should have included \"baz\" but was: #{last_line}"
    end

    test "blob doesn't trim off last incomplete line if not truncated" do
      blob = blob(name: "test.rb", content: "def foo(bar)\n\"baz\"", truncated: false)

      last_line = blob.colorized_lines.last
      assert last_line.include?("baz"), "last line should have included \"baz\" but was: #{last_line}"
    end

    test "preserves empty lines at the end of the file" do
      content = <<-EOF
<h2>Projects</h2>
<p>There are many exciting (new) <a href="projects/index.html">projects</a> that you can contribute to:</p>
<ul>
    <li>help us improve <a href="projects/compat/index.html">Website compatibility</a></li>
    <li>write <a href="projects/documentation/index.html">documentation</a></li>
    <li><a href="projects/svg/index.html">SVG</a></li>
    <li><a href="projects/mathml/index.html">MathML</a></li>
    <li><a href="projects/css/index.html">CSS</a></li>
    <li><a href="projects/dom/index.html">DOM</a></li>
</ul>


      EOF

      lines = blob(name: "test.html", content: content).colorized_lines
      assert_equal 12, lines.length
      assert lines.first.include?("<span class")
    end

    test "preserves empty lines at the end of the file when colorizing fails" do
      content = <<-EOF
<h2>Projects</h2>
<p>There are many exciting (new) <a href="projects/index.html">projects</a> that you can contribute to:</p>
<ul>
    <li>help us improve <a href="projects/compat/index.html">Website compatibility</a></li>
    <li>write <a href="projects/documentation/index.html">documentation</a></li>
    <li><a href="projects/svg/index.html">SVG</a></li>
    <li><a href="projects/mathml/index.html">MathML</a></li>
    <li><a href="projects/css/index.html">CSS</a></li>
    <li><a href="projects/dom/index.html">DOM</a></li>
</ul>


      EOF
      blob = blob(name: "test.html", content: content)
      blob.stubs(:tm_scope).returns(nil)

      lines = blob.colorized_lines
      assert_equal 12, lines.length
      assert_equal "&lt;h2&gt;Projects&lt;/h2&gt;", lines.first
    end

    test "returns HTML-safe strings" do
      line = blob(name: "test.rb", content: "class Foo <script> Bar").colorized_lines.first
      assert_predicate line, :html_safe?
      text = Nokogiri::HTML.parse(line).text
      assert_equal "class Foo <script> Bar", text
    end

    test "returns HTML-safe strings even for unknown file types" do
      line = blob(name: "test.rblolnotreally", content: "class Foo <script> Bar").colorized_lines.first
      assert_predicate line, :html_safe?
      text = Nokogiri::HTML.parse(line).text
      assert_equal "class Foo <script> Bar", text
    end

    test "works when treelights raises" do
      lines = blob(name: "test1.js", content: "a.b < 1").colorized_lines
      assert_equal "<span class='source.js'>a.b &lt; 1</span>", lines.first, "Syntax should be colorized"
      with_treelights_raising do
        lines = blob(name: "test1.js", content: "a.b < 1").colorized_lines
        assert_equal "a.b &lt; 1", lines.first, "Syntax should not be colorized"
      end
    end

    context "for staff (TextMate highlighting)" do
      test "highlights ruby" do
        content = <<-EOF
module Foo
  class Bar
    def initialize(baz, quux:)
      @baz = baz
      frobulate! if quux
    end
  end
end
        EOF

        lines = blob(name: "test.rb", content: content).colorized_lines
        assert_includes lines.first, "<span class="
      end

      test "returns HTML-safe strings" do
        line = blob(name: "test.rb", content: "class Foo <script> Bar").colorized_lines.first
        assert_predicate line, :html_safe?
        text = Nokogiri::HTML.parse(line).text
        assert_equal "class Foo <script> Bar", text
      end

      test "returns HTML-safe strings even for unknown file types" do
        line = blob(name: "test.rblolnotreally", content: "class Foo <script> Bar").colorized_lines.first
        assert_predicate line, :html_safe?
        text = Nokogiri::HTML.parse(line).text
        assert_equal "class Foo <script> Bar", text
      end

      test "caches its result on success or timeout, but not on RPC errors" do
        with_cache_enabled do
          # if highlighting succeeds, cache the result.
          fresh_lines = blob(name: "test1.js", content: "a.b < 1").colorized_lines
          GitHub::Colorize.stubs(:highlight_one).raises("Colorize shouldn't be called again!")
          cached_lines = blob(name: "test1.js", content: "a.b").colorized_lines
          assert_equal cached_lines, fresh_lines

          # if highlighting times out, cache the plain text result.
          GitHub::Colorize.stubs(:highlight_one).returns(nil)
          fresh_lines = blob(name: "test2.js", content: "c.d < 2").colorized_lines
          GitHub::Colorize.stubs(:highlight_one).raises("Colorize shouldn't be called again!")
          cached_lines = blob(name: "test2.js", content: "c.d < 2").colorized_lines
          assert_equal fresh_lines[0], "c.d &lt; 2"
          assert_equal cached_lines, fresh_lines

          # if highlighting raises a connection error, do not cache
          GitHub::Colorize.stubs(:highlight_one).raises(GitHub::Colorize::RPCError)
          fresh_lines = blob(name: "test3.js", content: "e.f < 3").colorized_lines
          GitHub::Colorize.unstub(:highlight_one)
          fresher_lines = blob(name: "test3.js", content: "e.f < 3").colorized_lines
          assert_equal fresh_lines[0], "e.f &lt; 3"
          refute_equal fresher_lines, fresh_lines
        end
      end
    end
  end

  context "colorized_lines_cache_key" do
    test "is different for blobs with different OIDs" do
      key1 = blob(name: "name.cpp", content: "content", oid: "a" * 40).colorized_lines_cache_key
      key2 = blob(name: "name.cpp", content: "content", oid: "b" * 40).colorized_lines_cache_key
      refute_equal key1, key2
    end

    test "is different for blobs with different file extensions" do
      key1 = blob(name: "name.cpp", content: "content").colorized_lines_cache_key
      key2 = blob(name: "name.rb", content: "content").colorized_lines_cache_key
      refute_equal key1, key2
    end

    test "is different for snippets/non-snippets" do
      blob = blob(name: "name.cpp", content: "content")
      snippet_blob = blob(name: "name.cpp", content: "content", snippet: true)
      refute_equal blob.colorized_lines_cache_key, snippet_blob.colorized_lines_cache_key
    end

    test "is different for truncated blobs" do
      content = "content"
      blob = blob(name: "name.cpp", content: content)
      truncated_blob = blob(name: "name.cpp", content: content, truncated: true)
      refute_equal blob.colorized_lines_cache_key, truncated_blob.colorized_lines_cache_key
    end
  end

  test "when lazy-loading, #data returns transcoded data the first time it's called" do
    repo = create(:repository, from_example: :encodings)

    blob = TreeEntry.new(repo, {
      "type" => "blob",
      "oid"  => "0baac26be61a8cc8dd90567a175feda900ff73fc",
      "path" => "files/处理篮球的投篮数据.md",
    })

    assert_equal Encoding::UTF_8, blob.data.encoding
  end

  # GitRPC can return binary encoded filenames, so we need a way to
  # access them as unicode for display
  test "add a method for accessing a scrubbed simplified path" do
    repo = create(:repository, from_example: :encodings)

    fn = "bad\x92enc.md".b
    blob = TreeEntry.new(repo, {
      "type" => "blob",
      "oid"  => "0baac26be61a8cc8dd90567a175feda900ff73fc",
      "path" => "files/bad\x92enc.md",
      "simplified_path" => fn,
    })

    assert_equal fn.force_encoding("utf-8").scrub!, blob.simplified_utf8_path
  end

  test "scrubbed simplified paths that are correctly encoded are returned" do
    repo = create(:repository, from_example: :encodings)

    fn = "日本語.md"

    blob = TreeEntry.new(repo, {
      "type" => "blob",
      "oid"  => "0baac26be61a8cc8dd90567a175feda900ff73fc",
      "path" => "files/#{fn}",
      "simplified_path" => fn,
    })

    assert_equal fn, blob.simplified_utf8_path
  end

  test "when can ask if transcoding is necessary" do
    repo = create(:repository, from_example: :encodings)

    utf8_blob = TreeEntry.new(repo, {
      "type" => "blob",
      "oid"  => "647f0dd6f6bc797c64286c66526f157cb20d7a1d",
      "path" => "README.md",
    })
    non_utf8_blob = TreeEntry.new(repo, {
      "type" => "blob",
      "oid"  => "0baac26be61a8cc8dd90567a175feda900ff73fc",
      "path" => "files/处理篮球的投篮数据.md",
    })

    # load blob data
    utf8_blob.data
    non_utf8_blob.data

    refute utf8_blob.transcoding_necessary?, "UTF-8 blob does not need transcoding"
    assert non_utf8_blob.transcoding_necessary?, "Non-UTF-8 blob does need transcoding"
  end

  test "returns UTF-8 encoded file extension" do
    repo = create(:repository, from_example: :encodings)

    utf8_blob = TreeEntry.new(repo, {
      "type" => "blob",
      "oid"  => "647f0dd6f6bc797c64286c66526f157cb20d7a1d",
      "path" => "README.一二三".b,
    })
    assert_equal ".一二三", utf8_blob.extension
  end

  context "attributes" do
    test "loads attributes" do
      commit = create_test_file

      tree_entry = blob(name: "foobar.rb", content: ":wave:", repo: @repo)
      TreeEntry.load_attributes!([tree_entry], commit.oid)

      expected_attributes = {
        "linguist-language" => "Java",
        "linguist-documentation" => "false",
        "linguist-vendored" => "false",
        "linguist-generated" => "false",
        "linguist-encoding" => "custom",
      }
      assert_equal expected_attributes, tree_entry.attributes
    end

    context "#documentation?" do
      test "linguist-documentation=false" do
        commit = create_test_file

        tree_entry = blob(name: "README.md", content: "does-not-matter", repo: @repo)
        TreeEntry.load_attributes!([tree_entry], commit.oid)

        assert_predicate tree_entry, :documentation?

        tree_entry.attributes = {
          "linguist-documentation" => "false",
        }

        refute_predicate tree_entry, :documentation?
      end

      test "-linguist-documentation" do
        commit = create_test_file

        tree_entry = blob(name: "README.md", content: "does-not-matter", repo: @repo)
        TreeEntry.load_attributes!([tree_entry], commit.oid)

        assert_predicate tree_entry, :documentation?

        tree_entry.attributes = {
          "linguist-documentation" => false,
        }

        refute_predicate tree_entry, :documentation?
      end
    end

    context "#generated?" do
      test "linguist-generated=false" do
        commit = create_test_file

        tree_entry = blob(name: "foobar.nib", content: "does-not-matter", repo: @repo)
        TreeEntry.load_attributes!([tree_entry], commit.oid)

        assert_predicate tree_entry, :generated?

        tree_entry.attributes = {
          "linguist-generated" => "false",
        }

        refute_predicate tree_entry, :generated?
      end

      test "-linguist-generated" do
        commit = create_test_file

        tree_entry = blob(name: "foobar.nib", content: "does-not-matter", repo: @repo)
        TreeEntry.load_attributes!([tree_entry], commit.oid)

        assert_predicate tree_entry, :generated?

        tree_entry.attributes = {
          "linguist-generated" => false,
        }

        refute_predicate tree_entry, :generated?
      end
    end

    context "#vendored?" do
      test "linguist-vendored=false" do
        commit = create_test_file

        tree_entry = blob(name: "vendor/foobar.rb", content: "does-not-matter", repo: @repo)
        TreeEntry.load_attributes!([tree_entry], commit.oid)

        refute_predicate tree_entry, :vendored?

        tree_entry.attributes = {
          "linguist-vendored" => "true",
        }
      end

      test "-linguist-vendored" do
        commit = create_test_file

        tree_entry = blob(name: "vendor/foobar.rb", content: "does-not-matter", repo: @repo)
        TreeEntry.load_attributes!([tree_entry], commit.oid)

        refute_predicate tree_entry, :vendored?

        tree_entry.attributes = {
          "linguist-vendored" => true,
        }
      end
    end

    test "#language" do
      commit = create_test_file

      tree_entry = blob(name: "foobar.rb", content: "does-not-matter", repo: @repo)
      TreeEntry.load_attributes!([tree_entry], commit.oid)

      assert_equal "Java", tree_entry.language.name

      tree_entry = blob(name: "foobar.rb", content: "does-not-matter", repo: @repo)
      TreeEntry.load_attributes!([tree_entry], commit.oid)

      tree_entry.attributes = {
        "linguist-language" => "Ruby",
      }
      assert_equal "Ruby", tree_entry.language.name
    end

    test "#encoding" do
      commit = create_test_file

      tree_entry = blob(name: "foobar.rb", content: "does-not-matter", repo: @repo)
      TreeEntry.load_attributes!([tree_entry], commit.oid)

      assert_equal "custom", tree_entry.encoding

      tree_entry = blob(name: "foobar.rb", content: "does-not-matter", repo: @repo)
      TreeEntry.load_attributes!([tree_entry], commit.oid)
      tree_entry.attributes = {
        "linguist-encoding" => "custom2",
      }
      assert_equal "custom2", tree_entry.encoding
    end

    test "#truncated_loc_and_sloc" do
      tree_entry = blob(name: "foobar.rb", content: "line one\nline two\n\nline four", repo: @repo, truncated: false)
      assert_equal tree_entry.truncated_loc, "4"
      assert_equal tree_entry.truncated_sloc, "3"

      tree_entry = blob(name: "foobar.rb", content: "line one\nline two\n\nline four", repo: @repo, truncated: true)
      assert_equal tree_entry.truncated_loc, "4+"
      assert_equal tree_entry.truncated_sloc, "3+"
    end
  end

  context "license?" do
    test "recognizes license files by name" do
      tree_entry = blob(name: "MIT-LICENSE", content: "")

      assert tree_entry.license?
    end

    test "reject non-license files by name" do
      tree_entry = blob(name: "README.md", content: "")

      refute tree_entry.license?
    end
  end

  context "blob?" do
    test "knows blobs are blobs" do
      tree_entry = blob(name: "blob", content: "")
      assert tree_entry.blob?
    end

    test "knows non-blobs are not blobs" do
      tree_entry = blob(name: "tree", content: "", type: "tree")
      refute tree_entry.blob?
    end
  end

  context "markdown?" do
    test "returns true for markdown files" do
      assert blob(name: "file.md", content: "").markdown?
      assert blob(name: "file.MD", content: "").markdown?
      assert blob(name: "file.mkdn", content: "").markdown?
      assert blob(name: "file.mdown", content: "").markdown?
      assert blob(name: "file.markdown", content: "").markdown?
    end

    test "returns false for non-markdowns" do
      refute blob(name: "file", content: "", type: "tree").markdown?
      refute blob(name: "file.txt", content: "", type: "tree").markdown?
    end
  end

  context "formatted?" do
    test "knows formatted blobs are formatted" do
      tree_entry = blob(name: "README.md", content: "")
      assert tree_entry.formatted?
    end

    test "knows plaintext blobs are not formatted" do
      tree_entry = blob(name: "README.txt", content: "")
      refute tree_entry.formatted?
    end

    test "knows other blobs are not formatted" do
      tree_entry = blob(name: "foo.bar", content: "")
      refute tree_entry.formatted?
    end
  end

  context "plaintext?" do
    test "knows plaintext blobs are plaintext" do
      tree_entry = blob(name: "README.txt", content: "")
      assert tree_entry.plaintext?
    end

    test "knows formatted blobs are not plaintext" do
      tree_entry = blob(name: "README.md", content: "")
      assert tree_entry.formatted?
      refute tree_entry.plaintext?
    end

    test "knows binary blobs are not plaintext" do
      tree_entry = blob(name: "README.jpg", content: "")
      tree_entry.data = nil
      refute tree_entry.plaintext?
    end
  end

  context "line endings" do
    test "identifies Unix line endings" do
      tree_entry = blob(name: "unix.txt", content: "the\ndude\nabides\n")
      assert tree_entry.has_unix_line_endings?
      assert tree_entry.has_only_unix_line_endings?
    end
    test "identifies Windows line endings" do
      tree_entry = blob(name: "windows.txt", content: "the\r\ndude\r\nabides\r\n")
      assert tree_entry.has_windows_line_endings?
      assert tree_entry.has_only_windows_line_endings?
    end
    test "identifies mixed line endings" do
      tree_entry = blob(name: "mixed.txt", content: "the\ndude\r\nabides\n")
      assert tree_entry.has_unix_line_endings?
      assert tree_entry.has_windows_line_endings?
      assert tree_entry.has_mixed_line_endings?
    end
    test "correctly handles blank file" do
      tree_entry = blob(name: "blank.txt", content: "")
      assert !tree_entry.has_unix_line_endings?
      assert !tree_entry.has_windows_line_endings?
      assert !tree_entry.has_mixed_line_endings?
    end
    test "correctly handles single-line file" do
      tree_entry = blob(name: "one-line.txt", content: "supercalifragilisticexpialidocious")
      assert !tree_entry.has_unix_line_endings?
      assert !tree_entry.has_windows_line_endings?
      assert !tree_entry.has_mixed_line_endings?
    end
    test "correctly handles mostly-blank Unix file" do
      tree_entry = blob(name: "unix-one-line.txt", content: "\n")
      assert tree_entry.has_unix_line_endings?
      assert !tree_entry.has_windows_line_endings?
      assert !tree_entry.has_mixed_line_endings?
    end
    test "correctly handles mostly-blank Windows file" do
      tree_entry = blob(name: "unix-one-line.txt", content: "\r\n")
      assert !tree_entry.has_unix_line_endings?
      assert tree_entry.has_windows_line_endings?
      assert !tree_entry.has_mixed_line_endings?
    end
    test "correctly handles mostly-blank mixed file" do
      tree_entry = blob(name: "mixed-newlines-only.txt", content: "\n\r\n\n")
      assert tree_entry.has_unix_line_endings?
      assert tree_entry.has_windows_line_endings?
      assert tree_entry.has_mixed_line_endings?
    end
  end

  context "#async_workflow" do
    test "returns nil when the workflow does not exist" do
      tree_entry = blob(name: ".github/workflows/main.yml", content: "name: Node CI")
      refute tree_entry.async_workflow.sync
    end

    test "returns the workflow when it exists" do
      path = ".github/workflows/main.yml"
      tree_entry = blob(name: path, content: "name: Node CI")
      workflow = Actions::Workflow.create(repository: tree_entry.repository, path: path, name: "")

      assert_equal workflow, tree_entry.async_workflow.sync
    end
  end

  test "returns correct plain text" do
    content = <<-EOF
module Foo
end
    EOF

    assert_equal blob(name: "test.rb", content: content).highlight_plain_lines, ["module Foo", "end"]
  end

  def create_test_file
    @repo.heads["master"].append_commit({
      message: "Add gitattributes commit",
      committer: @repo.owner }, @repo.owner) do |files|
      files.add(".gitattributes", "*.rb linguist-language=Java linguist-documentation=false linguist-vendored=false linguist-generated=false linguist-encoding=custom")
      files.add("foobar.rb", ":wave:")
    end
  end

  def blob(name:, content:, oid: "a" * 40, snippet: false, truncated: false, type: "blob", repo: create(:repository))
    info = {
      "type" => type,
      "oid"  => oid,
      "data" => content,
      "size" => content.bytesize,
      "path" => name,
      "truncated" => truncated,
    }
    TreeEntry.new(repo, info).tap do |entry|
      entry.snippet = snippet
    end
  end
end
