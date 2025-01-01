# typed: true
# frozen_string_literal: true

require "test_helper"

class LanguageAnalysisTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :language_test)
    @js_repo = create(:repository, from_example: :language_js)


    @repo.analyze_languages # so there's data
    @js_repo.analyze_languages # so there's data
  end

  setup do
    @analysis = LanguageAnalysis.new(@repo)
  end

  # This is what's calculated on-disk with the test repo
  def default_analysis
    {
      "HTML"       => 9997,
      "JavaScript" => 9478,
      "CSS"        => 3030,
      "Shell"      => 313,
    }
  end

  def stub_language_analysis(analysis_results)
    GitRPC::Client.any_instance.stubs(:language_stats).returns(analysis_results.stringify_keys)
    @repo.analyze_languages
  end

  test "combines (sums) analysis across multiple repositories" do
    combined_analysis = default_analysis.dup
    combined_analysis["JavaScript"] += 21  # the js repo is 21
    assert_equal combined_analysis.to_a, LanguageAnalysis.new([@repo, @js_repo]).language_sizes
  end

  context "#language_sizes" do
    test "retrieves the language data ordered by size" do
      assert_equal default_analysis.to_a, @analysis.language_sizes
    end
  end

  context "#language_percentages" do
    test "returns language breakdown percentages" do
      stats = @analysis.language_percentages
      stats = Hash[*stats.flatten]

      assert_operator stats["Shell"], :>, 0
      assert_operator stats["Shell"], :<, 2

      assert_operator stats["JavaScript"], :>, 30
      assert_operator stats["JavaScript"], :<, 50

      assert_equal 100, (stats["Shell"] + stats["JavaScript"] + stats["CSS"] + stats["HTML"]).round
    end

    test "rounds up any missing difference on the first result so the sum is 100" do
      # 14.44% gets rounded down, losing 0.08% (0.1% rounded) in total:
      # 14.4 + 14.4 + 17.1 == 99.9
      stub_language_analysis html: 7112, css: 1444, javascript: 1444

      percentages = @analysis.language_percentages
      assert_equal 100.0, percentages.sum(&:last).round(1)
      assert_equal 71.2, percentages.first[1], "should round up the HTML percentage by 0.1%"
    end

    test "returns percentages in descending order" do
      assert_equal %w(HTML JavaScript CSS Shell), @analysis.language_percentages.map(&:first)
    end
  end

  context "#language_summary" do
    test "summarizes all languages over the limit" do
      stub_language_analysis(
        c: 200, shell: 200, java: 200, scala: 200, ruby: 150,
        haskell: 20, javascript: 17, clojure: 13)

      assert_equal({ "Scala" => 20, "Java" => 20, "C" => 20, "Other" => 40 },
                   @analysis.language_summary(limit: 4))
    end

    test "limit defaults to 6 langs + Other" do
      stub_language_analysis(
        c: 200, shell: 200, java: 200, scala: 200, ruby: 150,
        haskell: 20, javascript: 17, clojure: 13)

      assert_equal({ "C" => 20, "Shell" => 20, "Java" => 20, "Scala" => 20,
                     "Ruby" => 15, "Haskell" => 2, "Other" => 3 },
                     @analysis.language_summary)
    end

    test "summarizes all languages below the percentage threshold" do
      stub_language_analysis(
        shell: 400, java: 400, ruby: 150,
        haskell: 41, javascript: 6, clojure: 3)

      assert_equal({ "Shell" => 40, "Java" => 40, "Ruby" => 15, "Other" => 5 },
                   @analysis.language_summary(threshold: 10))
    end

    test "threshold defaults to 1%" do
      stub_language_analysis(
        shell: 400, java: 400, ruby: 150,
        haskell: 41, javascript: 6, clojure: 3)

      assert_equal({ "Shell" => 40, "Java" => 40, "Ruby" => 15, "Haskell" => 4.1, "Other" => 0.9 },
                   @analysis.language_summary)
    end

    test "does not summarize the under-threshold langs if given the exact limit" do
      stub_language_analysis(
        c: 200, shell: 200, java: 200, scala: 200, ruby: 150,
        haskell: 41, javascript: 9) # JS is under the threshold

      assert_equal({ "C" => 20, "Shell" => 20, "Java" => 20, "Scala" => 20,
                     "Ruby" => 15, "Haskell" => 4.1, "JavaScript" => 0.9 },
                     @analysis.language_summary)
    end

    test "excludes languages with 0%" do
      stub_language_analysis(c: 75, shell: 25, java: 0, scala: 0)

      assert_equal({ "C" => 75, "Shell" => 25 }, @analysis.language_summary)
    end

    test "excludes langs with 0% before determining lang limit" do
      stub_language_analysis(c: 7500, shell: 1300, html: 700, ruby: 500, java: 2, scala: 1)

      assert_equal({ "C" => 75, "Shell" => 13, "Other" => 12 }, @analysis.language_summary(limit: 5, threshold: 10))
    end
  end
end
