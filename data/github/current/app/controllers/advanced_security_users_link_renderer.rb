# typed: true
# frozen_string_literal: true

class AdvancedSecurityUsersLinkRenderer < WillPaginate::ActionView::LinkRenderer
  # This param is referenced from javascript.
  # Check app/assets/modules/github/settings/advanced-security-usage-lists.ts
  # as well as test/js/unit/github/settings/test-advanced-security-usage-list.js
  PAGE_PARAM = :advanced_security_users_page

  # By default, the URL includes the full path to the page currently being
  # rendered. That path is the one being requested by AJAX, not the one the
  # user is looking at, so we don't want that.
  #
  # Also, changing the querystring to something more specific (rather than just
  # 'page') helps prevent potential conflicts with other paging on this page in
  # future.
  #
  # Note this url generation doesn't consider the page number of the Dependabot
  # repos list (also on the orgs security & analysis page), so that'll be reset
  # when switching page without using JavaScript (e.g. opening page in a new tab).
  # Under normal usage, where paging is handled by JavaScript and AJAX, the
  # currently-selected Dependabot page will be preserved. This felt like enough
  # of an edge case not to warrant the complicated code and coupling which
  # fixing it would introduce.
  def url(page)
    "?#{PAGE_PARAM}=#{page}"
  end
end
