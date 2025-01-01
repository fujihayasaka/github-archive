# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeOfConductTest < GitHub::TestCase
  fixtures do
    @repo_with_code_of_conduct = create :repository, from_example: :code_of_conduct_markdown

    @repo_without_code_of_conduct = create :repository, from_example: :code_of_conduct_none

    @repo_with_unknown_code_of_conduct = create :repository, from_example: :code_of_conduct_other

    @repo_with_blank_code_of_conduct = create :repository, from_example: :code_of_conduct_blank
  end

  context "#detect" do
    test "detects a code of conduct" do
      detected = CodeOfConduct.detect(@repo_with_code_of_conduct)
      assert detected
      assert_equal "contributor-covenant/version/1/4", detected.key
    end

    test "knows when there's no code of conduct" do
      refute CodeOfConduct.detect(@repo_without_code_of_conduct)
    end

    test "handles undetected codes of conduct" do
      detected = CodeOfConduct.detect(@repo_with_unknown_code_of_conduct)
      assert_equal "other", detected.key
    end

    test "detects a repo with an empty code of conduct as missing" do
      refute CodeOfConduct.detect(@repo_with_blank_code_of_conduct)
    end
  end

  test "recomended code of conduct is recomeneded" do
    assert_predicate CodeOfConduct.find("citizen-code-of-conduct"), :recommended?
  end

  test "non-recomended code of conduct is not recomended" do
    refute_predicate CodeOfConduct.find("no-code-of-conduct"), :recommended?
  end

  test "returns the description" do
    expected = "Recommended for projects of all sizes"
    assert_equal expected, CodeOfConduct.find("contributor-covenant").description
  end

  context "#generate" do
    test "substitutes standard fields in the transformed CoC" do
      params = {
        "community_name" => "Undead Unicorn",
        "contact_info"   => "octocat@github.com",
        "governing_body" => "Octocat Consortium",
      }
      template = CodeOfConduct.find_by_key("citizen-code-of-conduct")
      populated_template = template.generate(params)
      assert_includes populated_template, "A primary goal of Undead Unicorn"
      assert_includes populated_template, "all those who participate in Undead Unicorn"
      assert_includes populated_template, "please notify a community organizer as soon as possible. octocat@github.com"
      assert_includes populated_template, "you should notify Octocat Consortium"
      assert_includes populated_template, "octocat@github.com"
    end

    test "formats URLs correctly in the transformed CoC" do
      params = {
        "link_to_reporting_guidelines" => "http://www.myorg.com/reporting/",
        "link_to_policy" => "http://www.myorg.com/policies/",
      }
      template = CodeOfConduct.find_by_key("citizen-code-of-conduct")
      populated_template = template.generate(params)
      assert_includes populated_template, "[Policy](http://www.myorg.com/policies/)"
      assert_includes populated_template, "[Reporting guidelines](http://www.myorg.com/reporting/)"
    end

    test "disregards javascript:// URLs" do
      params = { "link_to_reporting_guidelines" => "javascript://alert('XSS!')" }
      template = CodeOfConduct.find_by_key("citizen-code-of-conduct")
      populated_template = template.generate(params)
      refute_includes populated_template, "[Reporting guidelines](javascript"
    end

    test "does not add a label to blank entries" do
      params = { "link_to_policy" => "" }
      template = CodeOfConduct.find_by_key("citizen-code-of-conduct")
      populated_template = template.generate(params)
      refute_includes populated_template, "Link to policy:"
    end
  end

  context "CodeOfConductTemplate" do
    test "knows if it's recomended" do
      assert_predicate CodeOfConduct.find("contributor-covenant"), :recommended?
      refute_predicate CodeOfConduct.find("no-code-of-conduct"), :recommended?
    end

    test "#description" do
      expected = "Recommended for projects of all sizes"
      assert_equal expected, CodeOfConduct.find("contributor-covenant").description
    end

    context "#legacy_key" do
      test "it exists" do
        assert_equal "contributor_covenant", CodeOfConduct.find("contributor-covenant").legacy_key
      end

      test "returns the underscored key when the code of conduct exists" do
        coc = @repo_with_code_of_conduct.code_of_conduct
        assert_equal coc.legacy_key, "contributor_covenant"
      end

      test "returns 'none' when the code of conduct does not exist" do
        coc = @repo_without_code_of_conduct.code_of_conduct
        assert_equal coc.legacy_key, "none"
      end

      test "returns 'other' when the coc is unknown" do
        coc = @repo_with_unknown_code_of_conduct.code_of_conduct
        assert_equal coc.legacy_key, "other"
      end

      test "returns none if the code of conduct is empty" do
        coc = @repo_with_blank_code_of_conduct.code_of_conduct
        assert_equal coc.legacy_key, "none"
      end
    end
  end

  test "return nil for url and path" do
    coc = CodeOfConduct.find("contributor-covenant")
    assert_nil coc.path
    assert_nil coc.url
  end

  context "class methods" do
    test "family helpers" do
      assert_equal "contributor-covenant", CodeOfConduct.find("contributor-covenant").family
      assert_equal "citizen-code-of-conduct", CodeOfConduct.find("citizen-code-of-conduct").family
      assert_equal "no-code-of-conduct", CodeOfConduct.find("no-code-of-conduct").family
      assert_equal "other", CodeOfConduct.find("other").key
      assert_equal "none", CodeOfConduct.find("none").key
    end

    test "returns all codes of conduct" do
      assert_equal 65, CodeOfConduct.all.count
    end

    test "returns recomended codes of conduct" do
      expected = %w(contributor-covenant citizen-code-of-conduct)
      assert_equal expected, CodeOfConduct.recommended.map(&:family)
    end

    context "#find_by_key" do
      test "find by Coconductor key" do
        assert CodeOfConduct.find_by_key("contributor-covenant/version/1/4")
      end

      test "find by legacy key" do
        assert CodeOfConduct.find_by_key("contributor_covenant")
      end

      test "find by family" do
        assert CodeOfConduct.find_by_key("contributor-covenant")
      end
    end

    context ".code_of_conduct_is_valid?" do
      test "returns true for a recommended coc" do
        assert_predicate CodeOfConduct.find("contributor-covenant"), :recommended?
        assert_predicate CodeOfConduct.find("citizen-code-of-conduct"), :recommended?
      end

      test "returns false for not found coc" do
        refute_predicate CodeOfConduct.find("other"), :recommended?
      end

      test "returns false for not recommended coc" do
        refute_predicate CodeOfConduct.find("no-code-of-conduct"), :recommended?
      end
    end
  end
end
