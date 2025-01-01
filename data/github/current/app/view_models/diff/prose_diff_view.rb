# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Diff

  class ProseDiffView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    FOLD_KEY = :unchanged
    ATTRS_WITH_TIPSIES = %w{href src}

    include FailbotHelper
    include OcticonsHelper
    include UrlHelpers
    include UrlHelper

    delegate :added?, :deleted?, :path, to: :diff
    attr_reader :repository, :diff, :render_url_base_params, :markup_helper, :format_helper, :before_html, :after_html, :html_diff

    def self.to_unsafe_params(raw_params)
      case raw_params
      when ActionController::Parameters then raw_params.to_unsafe_h
      else fail(StandardError, "Unable to cast parameters: #{raw_params}.")
      end
    end

    def after_initialize
      if added?
        @before_html = ActiveSupport::SafeBuffer.new("")
      elsif before_blob
        @before_html = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "before_html") do
          markup_helper.call(before_blob, path: before_blob.path, sanitize_orphan_hrefs: true)
        end
      else
        @before_html = nil
      end

      if deleted?
        @after_html = ActiveSupport::SafeBuffer.new("")
      elsif after_blob && !before_html.nil?
        @after_html  = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "after_html") do
          markup_helper.call(after_blob, path: after_blob.path, sanitize_orphan_hrefs: true)
        end
      else
        @after_html = nil
      end

      if @before_html && @after_html
        @html_diff = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "@html_diff") do
          GitHub.instrument "prose-diff.render", diff: diff, repository: repository do
            GitHub::HTML::Diff.new(@before_html, @after_html,
              render_url_base: safe_url_for(@render_url_base_params),
              unfold_icon: octicon("unfold", height: 24),
              moved_up_icon: octicon("arrow-up"),
              moved_down_icon: octicon("arrow-down")
            )
          end
        end
      end
    end

    def default_url_options
      uri = URI.parse(GitHub.url)
      {
        host: uri.host,
        protocol: uri.scheme,
      }
    end

    def html
      if html_diff
        @html ||= with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "diff_html") do
          format_helper.call(html_diff.html)
        end
      end
    end

    def has_visible_changes?
      html_diff.has_visible_changes? if html_diff
    end

    def before_blob
      return if diff.a_blob.nil?

      tree_entry = TreeEntry.load(repository, {
        "oid" => diff.a_blob,
        "path" => diff.a_path,
        "mode" => diff.a_mode,
        "type" => "blob",
      })

      tree_entry.data ? tree_entry : nil
    end

    def after_blob
      return if diff.b_blob.nil?

      tree_entry = TreeEntry.load(repository, {
        "oid" => diff.b_blob,
        "path" => diff.b_path,
        "mode" => diff.b_mode,
        "type" => "blob",
      })

      tree_entry.data ? tree_entry : nil
    end

    def large_blobs?
      before_blob.large? || after_blob.large?
    end

    def with_failbot_rescue(additional = {})
      yield
    rescue StandardError => e # rubocop:todo Lint/RescueException
      failbot(e, { app: "github-diff" }.merge(additional))
      nil
    end
  end
end
