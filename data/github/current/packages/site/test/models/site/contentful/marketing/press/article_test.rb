# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Press::ArticleTest < GitHub::TestCase
  unless GitHub.enterprise?
    context ".where" do
      test "returns first 3 press articles in descending order by date" do
        VCR.use_cassette("contentful/press-articles-get") do
          press_articles = Site::Contentful::Marketing::Press::Article.where(limit: 3, offset: 0)

          assert_equal("Microsoft’s AI Copilot Is Starting to Automate the Coding Industry", press_articles[0].title)
          assert_equal("Bloomberg", press_articles[0].publication)
          assert_equal(DateTime.parse("2024-04-17T00:00:00+00:00"), press_articles[0].date)

          assert_equal("GitHub Advanced Security with Jacob DePriest", press_articles[1].title)
          assert_equal("Hanselminutes", press_articles[1].publication)
          assert_equal(DateTime.parse("2024-04-11T00:00:00+00:00"), press_articles[1].date)

          assert_equal("GitHub gives tips to boost your career as software developers", press_articles[2].title)
          assert_equal("GC+", press_articles[2].publication)
          assert_equal(DateTime.parse("2024-04-11T00:00:00+00:00"), press_articles[2].date)

          assert_operator press_articles[0].date, :>=, press_articles[1].date
          assert_operator press_articles[1].date, :>=, press_articles[2].date

          assert_equal 3, press_articles.count
        end
      end

      test "skips the first 5 articles and returns the next 4 articles" do
        VCR.use_cassette("contentful/press-articles-get-skip") do
          press_articles = Site::Contentful::Marketing::Press::Article.where(limit: 4, offset: 5)

          assert_equal("Prompt in progress: GenAI text-to-code tools boost productivity", press_articles[0].title)
          assert_equal("The Economic Times", press_articles[0].publication)
          assert_equal(DateTime.parse("2024-04-07T00:00:00+00:00"), press_articles[0].date)

          assert_equal("GitHub COO Kyle Daigle on the “secret of good AI”", press_articles[1].title)
          assert_equal("Big Think", press_articles[1].publication)
          assert_equal(DateTime.parse("2024-04-04T00:00:00+00:00"), press_articles[1].date)

          assert_equal("「脱COBOL」が示す生成AIによるレガシープログラミング言語からの移行", press_articles[2].title)
          assert_equal("MONOist", press_articles[2].publication)
          assert_equal(DateTime.parse("2024-04-03T00:00:00+00:00"), press_articles[2].date)

          assert_equal("Just how good is AI-assisted code generation?", press_articles[3].title)
          assert_equal("ComputerWorld", press_articles[3].publication)
          assert_equal(DateTime.parse("2024-04-03T00:00:00+00:00"), press_articles[3].date)

          assert_equal 4, press_articles.count
        end
      end
    end

    test "#feed_json" do
      article = VCR.use_cassette("contentful/press-article") do
        Site::Contentful::Marketing::Press::Article.where(limit: 1).first
      end

      actual_json = article.feed_json

      assert actual_json[:active]
      refute actual_json[:featured]
      assert_equal article.title, actual_json[:article_title]
      assert_equal article.publication, actual_json[:publication]
      assert_equal article.url, actual_json[:article_url]
      assert_equal article.date, actual_json[:date]
      assert_equal article.date.strftime("%b %-d, %Y"), actual_json[:formatted_date]
    end
  end
end
