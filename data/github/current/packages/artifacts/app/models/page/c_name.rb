# typed: true
# frozen_string_literal: true

class Page::CName
  attr_reader :page, :cname

  DOMAIN_BLOCKLIST = %w{
    hackathonhowto.com
    githubflow.com
    py.codeconf.com
    wyg.io
    svnhub.com
    github.co.jp
    codeconf.com
    octoc.at
    octogatosconf.com
    git-merge.com
    blog.speakerdeck.com
    githubuniverse.com
    githubengineering.com
    choosealicense.com
    bear.ly
    b.logicalawesome.com
    githubconstellation.com
    githubindia.com
    githubbrazil.com
    githubbrasil.com
    analytics.githubassets.com
    ghcc.githubassets.com
  }.map { |domain| [domain, "www.#{domain}"] }.flatten

  GITHUB_DOMAINS = %w(
    github.com
    github.io
    github.net
    githubapp.com
    github.page
    githubusercontent.com
  )

  def initialize(page, cname)
    @page = page
    @cname = cname
  end

  # Public: Do the validation. Will raise a InvalidCNAME
  # error if the CName is invalid. Otherwise returns true.
  def validate
    validate_length
    validate_format
    validate_not_ip
    validate_not_double_www
    validate_uniqueness
    validate_not_github_com_cname
    validate_not_github_owned_pages
    validate_not_spammy
    validate_not_protected if GitHub.pages_domain_protection_enabled?
    true
  end

  # Check that the CNAME is in a valid format
  #
  # This is class level because it needs no state to check things.
  # It just does the Regexp validation.
  #
  # Raises InvalidCNAME if invalid
  def self.validate_format(cname)
    return if cname.blank?
    # (?u) enabled unicode matching for \w and \d
    if cname !~ /(?u)\A[\w][\w\-\.]+[\w\-]\z/ || !cname.include?(".") || cname.include?("..")
      url = self.cname_not_properly_formatted_url
      msg = "The custom domain `#{cname}` is not properly formatted. See #{url} for more information."
      raise Page::InvalidCNAME, msg
    end
  end

  def self.cname_not_properly_formatted_url
    "#{GitHub.help_url}/articles/troubleshooting-custom-domains/#github-repository-setup-errors"
  end

  def blocked_domain?
    DOMAIN_BLOCKLIST.include?(cname)
  end

  def github_domain?
    GITHUB_DOMAINS.include?(cname.split(".")[-2..-1].join("."))
  end

  private

  def validate_format
    self.class.validate_format(cname)
  end

  def validate_not_ip
    if cname =~ /\A\d+\.\d+\.\d+\.\d+\z/ || /\d\z/.match?(cname)
      url = self.class.cname_not_properly_formatted_url
      msg = "Your custom domain cannot be an IP address. See #{url} for more information."
      raise Page::InvalidCNAME, msg
    end
  end

  def validate_not_double_www
    if cname&.downcase&.start_with?("www.www.")
      url = self.class.cname_not_properly_formatted_url
      msg = "Your custom domain cannot start with 'www.www.'. See #{url} for more information."
      raise Page::InvalidCNAME, msg
    end
  end

  # Ensure this page's CNAME isn't already taken.
  #
  # Raises InvalidCNAME
  def validate_uniqueness
    return if cname.blank?

    GitHub.dogstats.time "pages.check_cname" do
      # we need to check uniqueness of alt CNAMEs
      # in both directions to prevent a case where two sites both have the same
      # alt CNAME. for example, if site A has a CNAME of example.com, and site
      # B has a CNAME of www.example.com, this will cause a conflict.

      cnames = [
        # direct CNAME conflict
        cname,
      ]

      # www-less alt already exists for another CNAME
      if cname.start_with?("www.")
        cnames << cname[4..-1]

      # www alt already exists for another CNAME
      else
        cnames << "www.#{cname}"
      end

      repo_with_same_cname = Page.where(cname: cnames).where.not(id: page.id).first&.repository
      unless repo_with_same_cname.nil?
        raise Page::InvalidCNAME, cname_in_use_message(repo_with_same_cname)
      end
    end
  end

  # Limit the cname length to 255 to avoid truncate by database column limit. https://github.com/github/pages-engineering/issues/107
  def validate_length
    return if cname.blank?
    raise Page::InvalidCNAME, "The custom domain cannot exceed 255 characters." if cname.length > 255
  end

  def cname_help_url
    "#{GitHub.help_url}/articles/setting-up-your-pages-site-repository/"
  end

  def cname_protected_help_url
    "#{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages"
  end

  def cname_management_help_url
    "#{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site"
  end

  def validate_not_github_com_cname
    return unless cname.present?

    return if page.owner.login == "github"

    return unless github_domain?

    repo_name = "#{page.owner}.#{GitHub.pages_host_name_v2}"
    names = [repo_name, "#{page.owner}.#{GitHub.pages_host_name_v1}"]

    if names.include?(cname) && names.include?(page.repository.name)
      raise Page::InvalidCNAME, "Your custom domain was ignored because this repository is automatically hosted from #{repo_name} already. See #{cname_help_url}"
    else
      raise Page::InvalidCNAME, "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named #{repo_name}. See #{cname_help_url}"
    end
  end

  # Sometimes we have DNS pointed to pages where there is no backing pages site.
  # This allows people to squat on GitHub-owned domains. Sometimes this can be
  # convincing phishing attacks, but most of the time they're just a slight
  # annoyance.
  def validate_not_github_owned_pages
    if blocked_domain? && !github_owned_page?
      raise Page::InvalidCNAME, cname_in_use_message
    end
  end

  def github_owned_page?
    page.owner.login == "github"
  end

  def validate_not_spammy
    if page.owner.spammy?
      raise Page::InvalidCNAME, "You cannot set a custom domain at this time."
    end
  end

  def cname_in_use_message(repo_with_same_cname = nil)
    if repo_with_same_cname&.owner == page.repository.owner
      owner_account_type = page.repository.owner.organization? ? "organization" : "account"
      return "The custom domain `#{cname}` is already taken by another repository in your #{owner_account_type}. Check out #{cname_management_help_url} for information about how to remove this domain from the other repository."
    end

    "The custom domain `#{cname}` is already taken. If you are the owner of this domain, check out #{cname_protected_help_url} for information about how to verify and release this domain."
  end

  def validate_not_protected
    return if cname.blank?

    # Get the domains in scope for protection (cname, parent of the cname and if cname is a www variant, one extra level of parent)
    domains = [cname, self.parent_domain, self.www_parent_domain].compact

    # If domain is protected & verified by owner at user/organization level, this cname can be used
    verified_by_owner = Page::ProtectedDomain
      .where(name: domains, state: %w[verified pending], owner: page.owner)
      .exists?
    return if verified_by_owner

    # If this domain is not verified by the page owner, but is verified by someone else, it can't be used
    verified_by_other = Page::ProtectedDomain
      .where(name: domains, state: %w[verified pending])
      .exists?
    raise Page::InvalidCNAME, "You must verify your domain #{cname} before being able to use it. Check out #{cname_protected_help_url} for more information." if verified_by_other
  end

  def parent_domain
    Page::ProtectedDomain.parent_domain_of(cname)
  end

  def www_parent_domain
    if cname&.downcase&.start_with?("www.")
      Page::ProtectedDomain.parent_domain_of(self.parent_domain)
    end
  end
end
