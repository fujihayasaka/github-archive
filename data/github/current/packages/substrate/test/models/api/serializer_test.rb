# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiSerializerTest < GitHub::TestCase
  module ExampleRelayObject
    extend self

    def global_relay_id
      "old-id"
    end
  end

  def setup_encoding_test(file_name: "foo.svg")
    org  = create(:organization)
    repo = create(:repository, owner: org)
    ref = repo.heads.find_or_build("master")
    original_sha = ref.sha
    @file_name = file_name
    ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
      files.add(@file_name, "")
    end
    @commit_sha = ref.sha
    diff = GitHub::Diff.new(repo, original_sha, @commit_sha)
    delta = diff.deltas.first
    @diff_entry = GitHub::Diff::Entry.from(diff: diff, delta: delta)
  end

  context "when encoding diff_url" do
    test "it encodes the character" do
      setup_encoding_test
      diff_url_encoding_ff = false
      repo_name = "testrepo"

      diff_url = Api::Serializer.diff_url(repo_name, @diff_entry)

      assert_equal "#{GitHub.url}/#{repo_name}/blob/#{@commit_sha}/#{@file_name}", diff_url
    end

    context "when the first character of the file path is special" do
      test "it encodes the characters" do
        file_name = "#bar#.svg"
        setup_encoding_test(file_name: file_name)
        diff_url_encoding_ff = true
        repo_name = "testrepo"

        diff_url = Api::Serializer.diff_url(repo_name, @diff_entry)

        assert_equal "#{GitHub.url}/#{repo_name}/blob/#{@commit_sha}/%23bar%23.svg", diff_url
      end
    end

    test "it encodes a space in the file name" do
      file_name = " foo bar.svg"
      setup_encoding_test(file_name: file_name)
      diff_url_encoding_ff = true
      repo_name = "testrepo"

      diff_url = Api::Serializer.diff_url(repo_name, @diff_entry)

      assert_equal "#{GitHub.url}/#{repo_name}/blob/#{@commit_sha}/%20foo%20bar.svg", diff_url
    end
  end

  context "when encoding diff_content_url" do
    test "it encodes the characters" do
      setup_encoding_test
      diff_url_encoding_ff = false
      repo_name = "testrepo"

      diff_contents_url = Api::Serializer.diff_contents_url(repo_name, @diff_entry)

      assert_equal "#{GitHub.api_url}/repos/#{repo_name}/contents/#{@file_name}?ref=#{@commit_sha}", diff_contents_url
    end

    context "when the first character of the file path is special" do
      test "it encodes the characters" do
        file_name = "#bar#.svg"
        setup_encoding_test(file_name: file_name)
        diff_url_encoding_ff = true
        repo_name = "testrepo"

        diff_contents_url = Api::Serializer.diff_contents_url(repo_name, @diff_entry)

        assert_equal "#{GitHub.api_url}/repos/#{repo_name}/contents/%23bar%23.svg?ref=#{@commit_sha}", diff_contents_url
      end
    end
  end

  context "when making global ids with options[:global_id_selection]" do
    test "does not log an error when the option is not missing or nil" do
      selection = {
        user_preference: true,
        user_opt_out: false
      }
      Platform::Helpers::GlobalId.expects(:for).with(ExampleRelayObject, **selection)

      Api::Serializer.send(:global_id_for, ExampleRelayObject, { global_id_selection: selection })
      assert_equal 0, Failbot.reports.size, "Valid calls don't make reports"
    end

    test "logs an error when the option is missing or nil" do
      Platform::Helpers::GlobalId.expects(:for).never

      Rails.env.stub(:production?, true) do
        assert_equal "old-id", Api::Serializer.send(:global_id_for, ExampleRelayObject, {})
      end

      assert_equal 1, Failbot.reports.size

      last_report = Failbot.reports.last
      backtrace = GitHub.enterprise? ? last_report["backtrace"] : last_report["exception_detail"][0]["stacktrace"]
      assert backtrace.present?

      Rails.env.stub(:production?, true) do
        assert_equal "old-id", Api::Serializer.send(:global_id_for, ExampleRelayObject, { global_id_selection: nil })
      end
      assert_equal 2, Failbot.reports.size
    end
  end
end
