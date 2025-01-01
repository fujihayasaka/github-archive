# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryLanguageAnalysisDependencyTest < GitHub::TestCase
  include PushTestHelper

  fixtures do
    @repo = create(:repository)
  end

  context "#top_languages_summarized" do
    test "it returns the top 6 languages in a repo" do
      languages = [
        ["C", 20],
        ["Shell", 20],
        ["Java", 20],
        ["Scala", 20],
        ["Ruby", 10],
        ["Haskell", 10],
      ]
      @repo.stubs(:language_percentages).returns languages.dup

      assert_equal languages, @repo.top_languages_summarized
    end

    test "it includes a sub-percent language if it's still nonzero" do
      languages = [["C", 90], ["Ruby", 9.9], ["Shell", 0.1]]
      @repo.stubs(:language_percentages).returns languages.dup
      assert_equal languages, @repo.top_languages_summarized
    end

    test "it elides 0-percentage languages" do
      languages = [["C", 100], ["Ruby", 0.0]]
      @repo.stubs(:language_percentages).returns languages.dup
      assert_equal [["C", 100]], @repo.top_languages_summarized
    end

    test "it rolls up any languages beyond the first 6 as 'Other'" do
      languages = [
        ["C", 20],
        ["Shell", 20],
        ["Java", 20],
        ["Scala", 20],
        ["Ruby", 10],
        ["Haskell", 5],
        ["Objective-C", 2.5],
        ["Clojure", 2.5],
      ]
      @repo.stubs(:language_percentages).returns languages.dup

      other = [
        ["C", 20],
        ["Shell", 20],
        ["Java", 20],
        ["Scala", 20],
        ["Ruby", 10],
        ["Haskell", 5],
        ["Other", 5],
      ]

      assert_equal other, @repo.top_languages_summarized
    end

    test "does not modify the languages value in-place (regression test)" do
      languages = [["C", 100], ["Ruby", 0.0]]
      copy = languages.dup
      @repo.stubs(:language_percentages).returns languages
      assert_equal [["C", 100]], @repo.top_languages_summarized
      assert_equal copy, languages
    end
  end

  context "#files_by_language" do
    test "empty repo with no branch" do
      assert_nil @repo.default_oid
      assert_equal Hash.new, @repo.files_by_language
    end


    test "empty repo with code" do
      empty_repo_with_code = create(:repository, from_example: :defunkt_ambition)
      refute_nil empty_repo_with_code.default_oid
      assert empty_repo_with_code.files_by_language.has_key?("Ruby")
    end
  end

  context "#includes_files_in_language?" do
    test "true if the repo contains files written in a given language" do
      repository = create :repository, from_example: :simple
      push_changes(repository: repository, changes: [
        { path: "config.rb", content: "require 'rails'" },
      ])
      repository.analyze_languages

      assert repository.includes_files_in_language?("Ruby")
      assert repository.includes_files_in_language?("ruby")
      refute repository.includes_files_in_language?("JavaScript")
      refute repository.includes_files_in_language?("C++")
    end
  end

  context "#copy_language_stats_from_repo" do
    test "does what it says on the tin" do
      parent = create(:repository)

      expected = [
        { language_name_id: create(:language_name).id, size: 128, public: true, total_size: 7 },
        { language_name_id: create(:language_name).id, size: 256, public: false, total_size: nil },
      ]

      expected.each { |data| parent.languages.create(data) }

      forker = create(:user)

      repo, _ = forker.fork(parent)
      repo.languages.create(language_name: expected.first[:language_name], size: 333)
      repo.copy_language_stats_from_repo(parent.id)
      repo.reload

      actual = repo.languages.map do |lang|
        lang.attributes.symbolize_keys.slice(:language_name_id, :size, :public, :total_size)
      end

      assert_equal expected, actual
    end
  end

  context "#update_primary_language!" do
    test "updates primary_language_name without overwriting other raw_data" do
      repo = create(:repository)
      language = create(:language).language_name

      # Simulate a different process updating raw_data on the repo
      Repository.find(repo.id).update!(lock_reason: "test")

      # The in memory model has no lock_reason
      assert_nil repo.lock_reason
      # But the database version does
      assert_equal "test", Repository.find(repo.id).lock_reason

      repo.update_primary_language!(language)

      # Both the primary language and the lock_reason should be persisted
      repo.reload
      assert_equal "test", repo.lock_reason
      assert_equal language.name, repo.primary_language_name
    end
  end

  context "#unset_primary_language!" do
    test "unsets primary_language_name without overwriting other raw_data" do
      repo = create(:repository)

      # Simulate a different process updating raw_data on the repo
      Repository.find(repo.id).update!(lock_reason: "test")

      # The in memory model has no lock_reason
      assert_nil repo.lock_reason
      # But the database version does
      assert_equal "test", Repository.find(repo.id).lock_reason

      repo.unset_primary_language!

      # The lock_reason should still be persisted
      repo.reload
      assert_equal "test", repo.lock_reason
    end
  end
end
