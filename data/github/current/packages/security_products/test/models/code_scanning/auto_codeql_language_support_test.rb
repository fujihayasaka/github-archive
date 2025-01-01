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

    test "returns actions if workflows exist", skip_enterprise: true do
      @repo.update(languages: [@javascript])
      @repo.workflows.create!(name: "Test", path: "test.yml", present_in_default_branch: true)

      supported_languages = language_support.supported_languages
      assert_includes supported_languages, "javascript-typescript"
      assert_includes supported_languages, "actions"
    end

    test "does not return actions if workflows exist but not in default branch", skip_enterprise: true do
      @repo.update(languages: [@javascript])
      @repo.workflows.create!(name: "Test", path: "test.yml", present_in_default_branch: false)

      supported_languages = language_support.supported_languages
      refute_includes supported_languages, "actions"
    end

    test "does not return actions if on GHES", enterprise_only: true do
      @repo.update(languages: [@javascript])
      @repo.workflows.create!(name: "Test", path: "test.yml", present_in_default_branch: true)

      supported_languages = language_support.supported_languages
      refute_includes supported_languages, "actions"
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

  context "get_language" do
    test "return the right language" do
      # The canonical name matches
      lang_obj = language_support.send(:get_language, "java-kotlin")
      refute_nil lang_obj
      assert lang_obj.canonical_name == "java-kotlin"

      # A variant name matches
      lang_obj = language_support.send(:get_language, "java")
      refute_nil lang_obj
      assert lang_obj.canonical_name == "java-kotlin"
    end
    test "includes swift" do
      lang_obj = language_support.send(:get_language, "swift")
      refute_nil lang_obj
      assert lang_obj.canonical_name == "swift"
    end
    test "includes rust with feature flag enabled for repo" do
      enable_feature_flag(:codeql_action_rust_analysis, @repo)
      disable_feature_flag(:codeql_action_rust_analysis, @org)
      lang_obj = language_support.send(:get_language, "rust")
      refute_nil lang_obj
      assert lang_obj.canonical_name == "rust"
    end
    test "includes rust with feature flag enabled for owner" do
      disable_feature_flag(:codeql_action_rust_analysis, @repo)
      enable_feature_flag(:codeql_action_rust_analysis, @org)
      lang_obj = language_support.send(:get_language, "rust")
      refute_nil lang_obj
      assert lang_obj.canonical_name == "rust"
    end
    test "exclude rust with feature flag disabled" do
      disable_feature_flag(:codeql_action_rust_analysis)
      assert_nil language_support.send(:get_language, "rust")
    end
  end

  context "detected_codeql_languages_build_mapping" do
    test "returns a mapping from lang to build mode" do
      @repo.language_analysis.stubs(:language_percentages).returns([["C", 1], ["Foobar", 1], ["C++", 1], ["JavaScript", 1]])

      build_mapping = language_support.detected_codeql_languages_build_mapping
      assert_equal 2, build_mapping.length
      assert_equal "autobuild", build_mapping[:"c-cpp"]
      assert_equal "none", build_mapping[:"javascript-typescript"]
    end

    test "returns buildless for Java" do
      @repo.language_analysis.stubs(:language_percentages).returns([["Java", 1]])

      build_mode = language_support.detected_codeql_languages_build_mapping[:"java-kotlin"]
      assert_equal "none # This mode only analyzes Java. Set this to 'autobuild' or 'manual' to analyze Kotlin too.", build_mode
    end

    test "returns autobuild for Java + Kotlin" do
      @repo.language_analysis.stubs(:language_percentages).returns([["Java", 1], ["Kotlin", 1]])

      assert_equal "autobuild",  language_support.detected_codeql_languages_build_mapping[:"java-kotlin"]
    end
  end

  context "detected_codeql_languages_string" do
    test "sets correct list of supported languages" do
      @repo.language_analysis.stubs(:language_percentages).returns([["C", 1], ["Foobar", 1], ["C++", 1], ["JavaScript", 1]])
      assert_equal "'c-cpp', 'javascript-typescript'", CodeScanning::AutoCodeqlLanguageSupport.new(@repo).detected_codeql_languages_string
    end
  end

end
