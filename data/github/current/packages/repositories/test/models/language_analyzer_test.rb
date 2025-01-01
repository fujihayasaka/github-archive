# typed: false
# frozen_string_literal: true

require "test_helper"

class LanguageAnalyzerTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :language_test)
  end

  setup do
    # Need a completely fresh record here, the tests were interacting badly with
    # resetting the serialized attributes every run.
    @repo = Repositories::Public.find_active!(@repo.id)
    @analyzer = LanguageAnalyzer.new(@repo)
    @analyzer.analyze
  end

  def default_analysis
    {
      "HTML"       => 9997,
      "JavaScript" => 9478,
      "CSS"        => 3030,
      "Shell"      => 313,
    }
  end

  def expected_existing_language_records
    [[language_record("Shell").id, "Shell", 313],
     [language_record("CSS").id, "CSS", 3030],
     [language_record("JavaScript").id, "JavaScript", 9478],
     [language_record("HTML").id, "HTML", 9997]]
  end

  def stub_language_analysis(analysis_results)
    GitRPC::Client.any_instance.stubs(:language_stats).returns(analysis_results)
  end

  def language_record(name)
    Language.where(repository_id: @repo.id).detect { |l| l.language_name.name == name }
  end

  context "#existing_language_records" do
    test "retrieves the language id, size and language_name name" do
      assert_equal expected_existing_language_records, @analyzer.existing_language_records
    end
  end

  context "#analyze" do
    test "analyzes a repository's languages and sets its primary language" do
      assert_equal %w(HTML JavaScript CSS Shell), @repo.language_breakdown.keys
      assert html = LanguageName.find_by_name("HTML")
      assert_equal html, @repo.primary_language
      assert_equal "HTML", @repo.primary_language_name
    end

    test "updates in-place a single language record when its value has changed" do
      assert html = language_record("HTML")
      assert js   = language_record("JavaScript")

      stub_language_analysis default_analysis.merge("HTML" => 10000)
      @analyzer.analyze

      assert html = Language.find(html.id) # in-place only
      assert js   = Language.find(js.id)
      assert_equal 10000, html.size
      assert_equal 9478, js.size
    end

    test "updates a repo's primary language to a new language if a new one becomes primary" do
      assert_equal "HTML", @repo.primary_language_name

      stub_language_analysis "JavaScript" => 10000
      @analyzer.analyze
      @repo.reload

      assert_equal "JavaScript", @repo.primary_language_name
    end

    test "inserts new language results when new results appear" do
      stub_language_analysis "Go" => 100
      @analyzer.analyze

      assert go = language_record("Go")
      assert_equal 100, go.size
    end

    test "removes language records when they are no longer present in the analysis" do
      assert html = language_record("HTML")

      stub_language_analysis default_analysis.except("HTML")
      @analyzer.analyze
      @repo.reload

      assert_equal "JavaScript", @repo.primary_language_name
      refute Language.find_by_id(html.id)
    end

    test "removes language records when they now have a zero size" do
      assert html = language_record("HTML")

      stub_language_analysis default_analysis.merge("HTML" => 0)
      @analyzer.analyze
      @repo.reload

      assert_equal "JavaScript", @repo.primary_language_name
      refute Language.find_by_id(html.id)
    end

    test "unsets the primary_language when a repository no longer has any detected languages" do
      assert_equal LanguageName.find_by_name("HTML"), @repo.primary_language
      stub_language_analysis({})
      @analyzer.analyze
      @repo.reload
      assert_equal [], @repo.language_breakdown.keys
      assert_nil @repo.primary_language_name_id
    end

    # This is a potential bug in linguist: there is data in the production db with
    # size = 0. Bug or not, defend against it.
    test "does not insert language records when the analyzed size is 0" do
      stub_language_analysis "HTML" => 0, "JavaScript" => 10
      @analyzer.analyze
      @repo.reload
      assert_equal %w(JavaScript), @repo.language_breakdown.keys
    end

    test "unsets a repo's primary language when only zero-size language stats are returned" do
      assert_equal "HTML", @repo.primary_language_name

      stub_language_analysis "HTML" => 0
      @analyzer.analyze
      @repo.reload

      assert_nil @repo.primary_language_name
      assert_nil @repo.primary_language
    end

  end

  context "#clear_analysis" do
    test "clears the primary language and all language entries for a repository" do
      assert_equal %w(HTML JavaScript CSS Shell), @repo.language_breakdown.keys
      assert_equal "HTML", @repo.primary_language_name

      @analyzer.clear_analysis
      @repo.reload

      assert_equal [], @repo.language_breakdown.keys
      assert_nil @repo.primary_language_name
    end
  end

end

class LanguageAnalyzerDiffTest < GitHub::TestCase
  fixtures do
    @html = LanguageName.lookup_by_name("HTML")
    @js   = LanguageName.lookup_by_name("JavaScript")
    @css  = LanguageName.lookup_by_name("CSS")
  end

  setup do
    @language_names = { "HTML" => @html, "JavaScript" => @js, "CSS" => @css }
  end

  test "returns inserts for new languages" do
    existing = []
    new_sizes = { "HTML" => 100, "JavaScript" => 200, "CSS" => 300 }
    diff = LanguageAnalyzer::Diff.new(new_sizes, existing, @language_names)
    assert_equal [[@html.id, 100], [@js.id, 200], [@css.id, 300]], diff.to_insert
    assert_equal [], diff.to_update
    assert_equal [], diff.to_delete
  end

  test "returns deletes for deleted languages" do
    existing = [
      [1, "HTML",       100],
      [2, "JavaScript", 200],
      [3, "CSS",        300],
    ]
    new_sizes = { "HTML" => 100, "CSS" => 300 }
    diff = LanguageAnalyzer::Diff.new(new_sizes, existing, @language_names)
    assert_equal [], diff.to_insert
    assert_equal [], diff.to_update
    assert_equal [2], diff.to_delete
  end

  test "returns updates for languages that have changed" do
    existing = [
      [1, "HTML",       100],
      [2, "JavaScript", 200],
      [3, "CSS",        300],
    ]
    new_sizes = { "HTML" => 100, "JavaScript" => 250, "CSS" => 300 }

    diff = LanguageAnalyzer::Diff.new(new_sizes, existing, @language_names)

    assert_equal [[2, 250]], diff.to_update
  end

  test "returns deletes for languages with a new size of 0 rather than updating" do
    existing = [
      [1, "HTML",       100],
      [2, "JavaScript", 200],
      [3, "CSS",        300],
    ]
    new_sizes = { "HTML" => 100, "JavaScript" => 0, "CSS" => 300 }

    diff = LanguageAnalyzer::Diff.new(new_sizes, existing, @language_names)

    assert_equal [], diff.to_update, "should not return an update any records"
    assert_equal [2], diff.to_delete, "should return a delete for the javascript record"
  end
end
