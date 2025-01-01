# typed: true
# frozen_string_literal: true

module Files
  class CloneURLView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers

    attr_reader :repository
    attr_reader :type
    attr_reader :is_default
    attr_reader :pushable

    def description
      case type
      when :gitweb
        "(read only) clone"
      when :subversion
        "checkout"
      else
        "clone"
      end
    end

    def protocol
      case type
      when :local
        "Local"
      when :ssh
        "SSH"
      when :http
        secure_http? ? "HTTPS" : "HTTP"
      when :gitweb
        "Git"
      when :subversion
        "Subversion"
      when :gh_cli
        "GitHub CLI"
      end
    end

    def url
      case type
      when :http
        repository.http_url
      when :local
        repository.local_url
      when :ssh
        repository.ssh_url
      when :gitweb
        repository.gitweb_url
      when :subversion
        repository.svn_url
      when :gh_cli
        host = GitHub.enterprise? ? "#{GitHub.host_name}/" : ""
        "gh repo clone #{host}#{repository.name_with_display_owner}"
      else
        raise ArgumentError, "unknown type: %p" % type
      end
    end

    # The URL to POST to to save a sticky selection
    def sticky_url
      user_set_protocol_path({
        protocol_selector: type.to_s,
        protocol_type: (pushable ? "push" : "clone"),
      })
    end

    def secure_http?
      !Rails.env.development?
    end

    def js_clone_class
      case type
      when :http
        "js-clone-url-http"
      when :ssh
        "js-clone-url-ssh"
      when :gh_cli
        "js-clone-url-gh-cli"
      end
    end
  end
end
