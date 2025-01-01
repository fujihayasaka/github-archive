# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Actions::GetReadmeHtmlTest < GitHub::TestCase
  setup do
    @repository = build(:repository)
    @action = build(:repository_action, repository: @repository)
  end

  context "#call" do
    context "when the action has a readme" do
      test("returns the readme html") do
        @action.stubs(:readme).returns(stub(path: "path"))
        GitHub::Goomba::MarkupPipeline.stubs(:to_html).returns("html")
        readme_html = Marketplace::Actions::GetReadmeHtml.new(repository_action: @action, selected_version: nil).call

        assert_equal "html", readme_html
      end
    end

    context "when the action does not have a readme" do
      test("returns nil") do
        @action.stubs(:readme).returns(nil)
        GitHub::Goomba::MarkupPipeline.stubs(:to_html).returns("html")
        readme_html = Marketplace::Actions::GetReadmeHtml.new(repository_action: @action, selected_version: nil).call

        assert_nil readme_html
      end
    end
  end
end
