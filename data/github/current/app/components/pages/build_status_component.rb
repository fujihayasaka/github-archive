# typed: true
# frozen_string_literal: true

module Pages
  class BuildStatusComponent < ApplicationComponent
    include SvgHelper

    def initialize(repository:)
      @repository = repository
    end

    def pages_unbuilt?
      !@repository.gh_pages_error? && !@repository.gh_pages_success?
    end

    def build_error?
      @repository.gh_pages_error?
    end

    # convert build error from markdown to safe html
    def build_error_message
      message_html(@repository.gh_pages_error) if build_error?
    end

    def gh_pages_url
      @repository.gh_pages_url
    end

    def must_verify_email?
      current_user.must_verify_email?
    end

    def spammy?
      spammy_user? || spammy_owner?
    end

    def spammy_user?
      current_user.spammy?
    end

    def spammy_owner?
      @repository.owner.spammy?
    end

    # convert error message to html
    # stripping block elements, since this message appears in dotcom
    # following guidelines at
    # https://thehub.github.com/engineering/development-and-ops/secure-coding/secure-coding-dotcom/safely-use-pipelines/#manual-html-building-vs-html_safe-aware-apis
    #
    # msg - markdown error string
    #
    # Returns an html_safe string if possible, else msg
    def message_html(msg)
      inline_allowlist = ::HTML::Pipeline::SanitizationFilter::WHITELIST.dup
      inline_allowlist[:elements] -= %w[p div]
      sanitizer = GitHub::Goomba::Sanitizer.from_allowlist(inline_allowlist)
      sanitizer.require_any_attributes(:a, "href", "id", "name")
      sanitizer.name_prefix = GitHub::Goomba::NAME_PREFIX

      context = { whitelist: inline_allowlist, sanitizer: sanitizer }
      GitHub::Goomba::MarkdownPipeline.to_html(msg, context, nil)
    end
  end
end
