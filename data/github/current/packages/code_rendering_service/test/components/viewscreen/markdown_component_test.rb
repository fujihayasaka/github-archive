# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/viewscreen_helpers"

class Viewscreen::MarkdownComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @user = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @user, name: "pod")
    @org = create(:organization, name: "org", admin: @user)
    @org_repo = create(:repository, owner: @org, name: "org-repo")
    @gist = create(:gist, owner: @user)
    @content = "This is a test"
    @check_suite = create(:check_suite)
  end

  Viewscreen::MarkdownComponent::SUPPORTED_VIEWS.keys.each do |render_type|
    if GitHub.enterprise?
      test "#{render_type} works in enterprise" do
        enable_if_flagged(render_type)

        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        assert view.supports_view?
      end

      test "#{render_type} generates the correct URL, without subdomain isolation" do
        enable_if_flagged(render_type)

        GitHub.subdomain_isolation = false
        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        url = view.iframe_url
        assert_match(%r|\Ahttps://github\.com/viewscreen/markdown/#{render_type}|, url.to_s)
        assert_includes url.query, "docs_host=#{CGI.escape(GitHub.help_url)}"
      end

      test "#{render_type} generates the correct URL, with subdomain isolation" do
        GitHub.subdomain_isolation = true
        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        url = view.iframe_url
        assert_match(%r|\Ahttps://viewscreen\.github\.com/markdown/#{render_type}|, url.to_s)
        assert_includes url.query, "docs_host=#{CGI.escape(GitHub.help_url)}"
      end
    end

    if !GitHub.enterprise?
      test "#{render_type} can create an iframe to viewscreen with the markdown content" do
        enable_if_flagged(render_type)

        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)

        render_inline(view)

        assert_selector ".js-render-needs-enrichment"
      end

      test "#{render_type} works" do
        enable_if_flagged(render_type)

        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)
        assert view.supports_view?
      end

      test "#{render_type} works with orgs" do
        if flagged_feature?(render_type)
          disable_feature_flag("markdown-#{render_type}")
          view = CodeRenderingService.for_markdown(render_type, @org, @content)
          refute view.supports_view?
        end

        enable_if_flagged(render_type, @org)

        view = CodeRenderingService.for_markdown(render_type, @org, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)
        assert view.supports_view?
      end

      test "#{render_type} works with repos owned by allowed orgs" do
        if flagged_feature?(render_type)
          disable_feature_flag("markdown-#{render_type}")
          view = CodeRenderingService.for_markdown(render_type, @org_repo, @content)
          refute view.supports_view?
        end

        enable_if_flagged(render_type, @org)

        view = CodeRenderingService.for_markdown(render_type, @org_repo, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)
        assert view.supports_view?
      end

      test "#{render_type} works with gists" do
        if flagged_feature?(render_type)
          disable_feature_flag("markdown-#{render_type}")
          view = CodeRenderingService.for_markdown(render_type, @gist, @content)
          refute view.supports_view?
        end

        enable_if_flagged(render_type, @gist.owner)

        view = CodeRenderingService.for_markdown(render_type, @gist, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)
        assert view.supports_view?
      end

      test "#{render_type} works with check suites" do
        if flagged_feature?(render_type)
          disable_feature_flag("markdown-#{render_type}")
          view = CodeRenderingService.for_markdown(render_type, @check_suite, @content)
          refute view.supports_view?
        end

        enable_if_flagged(render_type, @check_suite.repository)

        view = CodeRenderingService.for_markdown(render_type, @check_suite, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)
        assert view.supports_view?
      end

      test "viewscreen #{render_type} generates a valid url" do
        enable_if_flagged(render_type)
        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)

        url = view.iframe_url
        query = Rack::Utils.parse_query(url.query)

        assert_equal "viewscreen.githubusercontent.com", url.host
        assert_equal "/markdown/#{render_type}", url.path
        assert_includes url.query, "docs_host=#{CGI.escape(GitHub.help_url)}"
      end

      test "viewscreen #{render_type} sets viewdata_as_json correctly" do
        enable_if_flagged(render_type)
        view = CodeRenderingService.for_markdown(render_type, @repo, @content)
        assert_equal({ data: @content }.to_json, view.viewdata_as_json)
      end

      test "#{render_type} " do
        if flagged_feature?(render_type)
          disable_feature_flag("markdown-#{render_type}")
          enable_if_flagged(render_type, @repo)
        end

        view = CodeRenderingService.for_markdown(render_type, @user, @content)
        assert view.is_a?(Viewscreen::MarkdownComponent)
        refute view.supports_view?
      end

      test "#{render_type} does not work with feature flag disabled" do
        if flagged_feature?(render_type)
          disable_feature_flag("markdown-#{render_type}")
          view = CodeRenderingService.for_markdown(render_type, @repo, @content)
          assert view.is_a?(Viewscreen::MarkdownComponent)
          refute view.supports_view?
        end
      end
    end
  end

  def enable_if_flagged(render_type, entity = nil)
    if flagged_feature?(render_type)
      if entity
        enable_feature_flag("markdown-#{render_type}", entity)
      else
        enable_feature_flag("markdown-#{render_type}")
      end
    end
  end

  def flagged_feature?(render_type)
    Viewscreen::MarkdownComponent::FLAGGED_FEATURES.include?(render_type)
  end
end
