# typed: true
# frozen_string_literal: true

class EditRepositories::AdminScreen::PagesStatusView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  # cname_error passed by controller after DNS check, build_error in model
  attr_reader :repository, :cname_error, :user

  # legacy info message - remove?
  def pages_unbuilt?
    !repository.gh_pages_error? && !repository.gh_pages_success?
  end

  def build_error?
    repository.gh_pages_error?
  end

  # convert build error from markdown to safe html
  def build_error_message
    message_html(repository.gh_pages_error) if build_error?
  end

  def cname_error?
    cname_error.present?
  end

  # convert cname error from markdown to safe html
  def cname_error_message
    message_html(cname_error) if cname_error?
  end

  def gh_pages_url
    repository.gh_pages_url
  end

  def must_verify_email?
    user.must_verify_email?
  end

  def spammy?
    spammy_user? || spammy_owner?
  end

  def spammy_user?
    user.spammy?
  end

  def spammy_owner?
    repository.owner.spammy?
  end

  def plan_supports_pages?
    repository.plan_supports_pages?
  end

  private

  # convert error message to html
  # stripping block elements, since this message appears in dotcom
  # following guidelines at
  # https://github.com/github/security-docs/blob/master/standards/Secure%20Coding%20Principles.md#server-side-html-generation
  #
  # msg - markdown error string
  #
  # Returns an html_safe string if possible, else msg
  def message_html(msg)
    inline_allowlist = ::HTML::Pipeline::SanitizationFilter::ALLOWLIST.dup
    inline_allowlist[:elements] -= %w[p div]
    sanitizer = GitHub::Goomba::Sanitizer.from_allowlist(inline_allowlist)
    sanitizer.require_any_attributes(:a, "href", "id", "name")
    sanitizer.name_prefix = GitHub::Goomba::NAME_PREFIX

    context = { allowlist: inline_allowlist, sanitizer: sanitizer }
    GitHub::Goomba::MarkdownPipeline.to_html(msg, context, nil)
  end

end
