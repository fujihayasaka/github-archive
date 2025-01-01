# typed: false
# frozen_string_literal: true

require "test_helper"

class GistsSnippetViewTest < GitHub::TestCase
  fixtures do
    @staff_user = create(:staff_admin_user)
    @user = create(:user)
    @spammy_user = create(:user, spammy: true)

    contents = [
      { name: "hello.rb", value: "def hello; puts 'Hello!'; end" },
    ]

    @gist = GistHelpers.generate(user: @staff_user, contents: contents)
  end

  context "#blob" do
    test "returns the first 10 lines of a gist with many short lines" do
      contents = [
        { name: "12-lines.rb", value: "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl" },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert view.blob.data.ends_with?("j")
    end

    test "returns the first 1024 bytes of a gist, if that comes before 11 lines" do
      contents = [
        { name: "2000-bytes.rb", value: "*" * 2000 },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert_equal view.blob.data.length, 1024
    end

    test "for markdown gists, does not cut html elements in half" do
      contents = [
        { name: "cutoff.md", value: ("*" * 1015) + "<img src='url' />" },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert view.blob.data.ends_with?("*")
    end

    test "for markdown gists, cuts html elements in half if they're in a code block" do
      contents = [
        { name: "cutoff.md", value: "test\n ```\n#{("*" * 999)}<img src='url' />" },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert view.blob.data.ends_with?("<img src='url' ")
    end

    test "for non-markdown gists, does cut html elements in half" do
      contents = [
        { name: "cutoff.txt", value: ("*" * 1015) + "<img src='url' />" },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert view.blob.data.ends_with?("<img src=")
    end

    test "for markdown gists, truncates renderables with > characters properly" do
      nodes = (1..100).collect_concat { |i| "  #{i} --> potato" }.join("\n")
      contents = [
        { name: "cutoff.md", value: "```mermaid\nflowchart LR\n#{nodes}```" },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert view.blob.data.ends_with?("  8 --> potato")
    end

    test "for markdown gists, where the last line is a blockquote it truncates properly" do
      nodes = [
        "foo",
        "> bar"
      ].flatten.join("\n")
      contents = [
        { name: "cutoff.md", value: nodes },
      ]

      gist = GistHelpers.generate(user: @staff_user, contents: contents)
      view = Gists::SnippetView.new(gist: gist, current_user: @staff_user)
      assert view.blob.data.ends_with?("> bar")
    end
  end

  context "Stargazer counts" do
    if GitHub.spamminess_check_enabled? #spamminess checks are not enabled on Enterprise
      test "return star count for Gist excluding spammy user when regular user" do
        @user.star(@gist)
        @spammy_user.star(@gist)

        view = Gists::SnippetView.new(gist: @gist, current_user: @user)

        assert_equal "1 star", view.star_count_info
      end

      test "return star count for Gist excluding spammy user when logged out/nil" do
        @user.star(@gist)
        @spammy_user.star(@gist)

        view = Gists::SnippetView.new(gist: @gist, current_user: nil)

        assert_equal "1 star", view.star_count_info

        view = Gists::SnippetView.new(gist: @gist, current_user: false)

        assert_equal "1 star", view.star_count_info
      end
    end

    test "return star count for Gist including spammy user when staff" do
      @user.star(@gist)
      @spammy_user.star(@gist)

      view = Gists::SnippetView.new(gist: @gist, current_user: @staff_user)

      assert_equal "2 stars", view.star_count_info
    end

    test "return star count for Gist including spammy user when spammy user" do
      @user.star(@gist)
      @spammy_user.star(@gist)

      view = Gists::SnippetView.new(gist: @gist, current_user: @spammy_user)

      assert_equal "2 stars", view.star_count_info
    end
  end

  context "#comment_count_info" do
    test "does not cause extra queries" do
      create_list(:gist_comment, 2, gist: @gist)

      GitHub::PrefillAssociations.prefill_batch_method([@gist], :comment_count)

      assert_no_queries do
        view = Gists::SnippetView.new(gist: @gist, current_user: @spammy_user)

        assert_equal "2 comments", view.comment_count_info
      end
    end

    test "considers disabled comments" do
      enable_feature_flag(:gist_comment_moderation)

      create_list(:gist_comment, 2, gist: @gist)
      @gist.update!(comments_enabled: false)

      GitHub::PrefillAssociations.prefill_batch_method([@gist], :comment_count)

      assert_no_queries do
        view = Gists::SnippetView.new(gist: @gist, current_user: @spammy_user)

        assert_equal "0 comments", view.comment_count_info
      end
    end
  end
end
