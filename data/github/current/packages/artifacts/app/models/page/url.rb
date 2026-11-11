# typed: true
# frozen_string_literal: true

class Page::URL
  attr_reader :page

  def initialize(page)
    @page = page
  end

  delegate :owner, to: :page

  # The custom domain inherited from the user page, if this is a project page and
  # the user page has a CNAME. Otherwise, it returns nil.
  def async_inherited_cname
    return Promise.resolve(nil) unless GitHub.pages_custom_cnames?

    Promise.all([page.async_primary?, page.async_owner]).then do |is_primary, owner|
      next if is_primary # this *is* the primary repository for the user so we goooood
      owner.async_user_pages_repo.then do |user_pages_repo|
        next unless user_pages_repo
        user_pages_repo.async_page.then do |user_page|
          next unless user_page
          user_page.cname
        end
      end
    end
  end

  # The host name this page will be served from if it didn't have its own CNAME
  # Returns a Promise.
  def async_default_host_name
    async_inherited_cname.then do |inherited_cname|
      next inherited_cname unless inherited_cname.nil?
      async_user_host_name
    end
  end

  # Return the default TLD + SLD for the this Page, e.g., `github.io`, or `github.com`
  def async_pages_host_name
    # Private pages always end in `github.io`, even if it's a github-owned page which normally ends in `.com`
    if page.private?
      GitHub.pages_host_name_v2
    else
      page.async_owner.then(&:pages_host_name)
    end
  end

  # Return the default TRD + TLD + SLD for this *user* e.g., `hubot.github.io`
  def async_user_host_name
    Promise.all([page.async_owner, async_pages_host_name]).then do |owner, pages_host_name|
      "#{owner.to_s.downcase}.#{pages_host_name}"
    end
  end

  # Return the Subdomain + TLD + SLD for a *project* page e.g., `my-project.hubot.github.io`
  def async_subdomain_host_name
    page.async_repository.then do |repository|
      subdomain_name = repository.page.subdomain.to_s.downcase
      "#{subdomain_name}.pages.#{GitHub.pages_host_name_v2}" # pages with subdomains are always on github.io
    end
  end

  def proxima_host
    "#{@page.display_routed_subdomain_proxima}.#{GitHub.pages_host_name_proxima}"
  end

  # The path, relative to the domain root, from which this site can be accesssed
  #
  # This will be:
  #  * `/` for CNAME'd domains
  #  * `/` for sites on subdomains
  #  * `/pages/user/` for user pages on Enterprise without subdomain isolation
  #  * `/pages/user/repo/` for project pages on Enterprise without subdomain isolation
  #  * `/user/` for user pages on Enterprise with subdomain isolation
  #  * /user/repo/ for project pages on enterprise with subdomain isolation
  #  * `/` for user pages on .com
  #  * `/repo` for project pages on .com
  #
  # Response will always include a trailing slash
  def async_path
    return Promise.resolve("/") if GitHub.pages_custom_cnames? && page.cname
    return Promise.resolve("/") if page.subdomain

    page.async_repository.then do |repository|
      Promise.all([repository.async_owner, page.async_primary?]).then do |owner, is_primary|
        path = [""]
        path << "pages" unless GitHub.subdomain_isolation?
        path << owner   unless GitHub.pages_custom_cnames?
        path << "#{repository.name}" unless is_primary
        path.join("/") + "/"
      end
    end
  end

  # The pages host endpoint
  #
  # This will be
  #   * the CNAME of this page
  #   * `<subdomain>.github.io` if page has a subdomain (private pages)
  #   * the inherited CNAME if this is a project page, and the user page has a CNAME
  #   * `<username>.github.io` on .com
  #   * `pages.<GitHub.host_name>` on Enterprise with subdomain isolation
  #   * `<GitHub.host_name>` on Enterprise with subdomain isolation
  #   * `<subdomain>.pages.<tenant>.ghe.com` on proxima (multi tenant enterprise)
  def async_host
    return Promise.resolve(proxima_host) if GitHub.multi_tenant_enterprise?

    return Promise.resolve(page.cname) if GitHub.pages_custom_cnames? && page.cname

    return async_subdomain_host_name if !GitHub.enterprise? && page.subdomain

    return async_default_host_name if GitHub.pages_custom_cnames?

    async_pages_host_name
  end

  def host
    async_host.sync
  end

  def scheme
    if GitHub.enterprise?
      GitHub.ssl? ? "https" : "http"
    else
      page.https_redirect? ? "https" : "http"
    end
  end

  def async_custom_domain?
    Promise.all([async_host, async_pages_host_name]).then do |host, pages_host_name|
      host != pages_host_name
    end
  end

  def async_to_s
    Promise.all([async_host, async_path]).then do |host, path|
      Addressable::URI.new(scheme: scheme, host: host, path: path).normalize.to_s
    rescue Addressable::URI::InvalidURIError
      "[Invalid URI]"
    end
  end

  # The absolute URL from which this Page can be accessed by users
  def to_s
    async_to_s.sync
  end
end
