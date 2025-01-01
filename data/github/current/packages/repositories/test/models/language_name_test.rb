# typed: true
# frozen_string_literal: true

require "test_helper"

class LanguageNameTest < GitHub::TestCase
  LinguistLanguageMock = Struct.new(:name, :id, :language_id)
  fixtures do
    @js         = create :language_name, name: "JavaScript", linguist_id: 183
    @ruby       = create :language_name, name: "Ruby", linguist_id: 326
    @repo_ruby1 = create :repository, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_ruby_1
    @repo_ruby2 = create :repository, owner: @repo_ruby1.owner, created_at: 6.hours.ago, pushed_at: 6.hours.ago, from_example: :language_ruby_2
    @repo_js1   = create :repository, owner: @repo_ruby1.owner, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_js

    [@repo_ruby1, @repo_ruby2, @repo_js1].each { |r| r.analyze_languages }
  end

  test "caches #primary_language_name string on repos" do
    assert_equal @repo_ruby1.primary_language.name, @repo_ruby1.primary_language_name
  end

  test "User#calculate_primary_language" do
    assert_equal "Ruby", @repo_ruby1.owner.calculate_primary_language!.try(:name)
    assert_equal "Ruby", LanguageName.find_by!(id: @repo_ruby1.owner.primary_language_name_id).name
  end

  test ".clean_name and #clean_name" do
    {
      "C" => "c",
      "C#" => "csharp",
      "C++" => "cplusplus",
      "C-ObjDump" => "c_objdump",
      "Cap'n Proto" => "cap_n_proto",
      "F*" => "fstar",
      "Graphviz (DOT)" => "graphviz_dot",
      "HTML+PHP" => "htmlplusphp",
      "Jupyter Notebook" => "jupyter_notebook",
      "Ruby" => "ruby",
      "robots.txt" => "robotsdottxt",
      "" => "",
    }.each do |input, expected|
      assert_equal expected, LanguageName.clean_name(input)
      assert_equal expected, LanguageName.new(name: input).clean_name
    end
  end

  context "when looking up languages" do
    test "creates languages that do not exist" do
      assert_nil LanguageName.find_by(name: "Go"), "'Go' should not be in the database"

      language_name = LanguageName.lookup_by_name("Go")
      assert language_name, "'Go' was not successfully created"

      assert_equal 132, language_name.linguist_id, "'Go' Linguist ID is incorrect"
    end

    test "returns languages that already exist" do
      assert LanguageName.find_by(name: "Ruby"), "'Ruby' should be in the database"
      language_name = LanguageName.lookup_by_name("Ruby")

      assert language_name, "'Ruby' was returned"
      assert_equal 326, language_name.linguist_id, "'Ruby' Linguist ID is incorrect"
    end

    test "returns `nil` for unknown languages" do
      assert_nil LanguageName.lookup_by_name("YabbaDabbaDoo"), "Flinstone is not a valid language"
    end
  end

  context "#lookup_by_names" do
    test "finds languages that already exist" do
      existing_language = create(:language_name)

      result = LanguageName.lookup_by_names([existing_language.name])

      assert_equal [existing_language], result
    end

    test "creates Linguist-supported languages that don't already exist" do
      new_language = LanguageName.new(name: "A new language")
      linguist_language = LinguistLanguageMock.new(name: "A new language", id: 1)

      Linguist::Language.stub(:find_by_name, linguist_language) do
        @result = LanguageName.lookup_by_names([new_language.name])
      end

      language_name = LanguageName.where(name: new_language.name).first
      assert_equal [language_name], @result
    end

    test "returns nil for non-Linguist languages that don't already exist" do
      new_language = LanguageName.new(name: "A new language")

      Linguist::Language.stub(:find_by_name, nil) do
        Linguist::Language.stub(:find_by_alias, nil) do
          @result = LanguageName.lookup_by_names([new_language.name])
        end
      end

      assert_equal [nil], @result
    end
  end
end
