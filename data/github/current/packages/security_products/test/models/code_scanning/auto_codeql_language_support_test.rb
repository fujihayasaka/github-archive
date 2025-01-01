# typed: true
# frozen_string_literal: true

require "test_helper"

class AutoCodeqlLanguageSupportTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, :minimal, owner: @org)

    @ruby = create(:language, language_name: create(:language_name, name: "Ruby"))
    @python = create(:language, language_name: create(:language_name, name: "Python"))
    @java = create(:language, language_name: create(:language_name, name: "Java"))
    @bash = create(:language, language_name: create(:language_name, name: "Bash"))
    @kotlin = create(:language, language_name: create(:language_name, name: "Kotlin"))
    @javascript = create(:language, language_name: create(:language_name, name: "JavaScript"))
    @typescript = create(:language, language_name: create(:language_name, name: "TypeScript"))
  end

  def language_support
    CodeScanning::AutoCodeqlLanguageSupport.new(@repo)
  end

  context "supported_languages" do
    test "returns supported languages" do
      @repo.update(languages: [@bash, @ruby, @java])

      supported_languages = language_support.supported_languages
      assert_equal 2, supported_languages.length
      assert_includes supported_languages, "ruby"
      assert_includes supported_languages, "java-kotlin"
    end

    test "returns combined languages" do
      @repo.update(languages: [@java, @kotlin])

      supported_languages = language_support.supported_languages
      assert_equal 1, supported_languages.length
      assert_includes supported_languages, "java-kotlin"
    end
  end

  context "non_repo_languages_present?" do
    test "returns true if a non-repo language is present" do
      @repo.update(languages: [@java])

      assert language_support.non_repo_languages_present?(%w[java-kotlin ruby])
    end

    test "returns false if no non-repo language is present" do
      @repo.update(languages: [@java, @ruby])

      refute language_support.non_repo_languages_present?(%w[java-kotlin ruby])
    end
  end

  test "canonical_names" do
    assert_equal [], language_support.canonical_names([])
    assert_equal [], language_support.canonical_names(["bash"])
    assert_equal ["java-kotlin"], language_support.canonical_names(["java"])
    assert_equal ["java-kotlin"], language_support.canonical_names(["java-kotlin"])
  end

  test "display_names" do
    @repo.update(languages: [@javascript, @kotlin, @java])
    assert_equal ["JavaScript"], language_support.display_names["javascript-typescript"]
    assert_equal %w[Java Kotlin], language_support.display_names["java-kotlin"]

    ts_repo = create(:private_repository, :minimal, owner: @org)
    ts_repo.update(languages: [@typescript])
    ls = CodeScanning::AutoCodeqlLanguageSupport.new(ts_repo)
    assert_equal ["TypeScript"], ls.display_names["javascript-typescript"]
  end

  context "language_data" do
    test "includes swift" do
      assert language_support.send(:language_data).any? { |lang| lang[:canonical_name] == "swift" }
    end
  end

  context "get_language" do
    test "return the right language" do
      # The canonical name matches
      lang_obj = language_support.send(:get_language, "java-kotlin")
      refute_nil lang_obj
      assert lang_obj[:canonical_name] == "java-kotlin"

      # A variant name matches
      lang_obj = language_support.send(:get_language, "java")
      refute_nil lang_obj
      assert lang_obj[:canonical_name] == "java-kotlin"
    end
  end
end
