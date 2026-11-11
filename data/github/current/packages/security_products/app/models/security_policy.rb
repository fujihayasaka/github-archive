# typed: true
# frozen_string_literal: true

# A security policy for a repository stored in a SECURITY.md file.
class SecurityPolicy
  FILENAME = "SECURITY.md".freeze

  TEMPLATE = <<~MD.freeze
    # Security Policy

    ## Supported Versions

    Use this section to tell people about which versions of your project are
    currently being supported with security updates.

    | Version | Supported          |
    | ------- | ------------------ |
    | 5.1.x   | :white_check_mark: |
    | 5.0.x   | :x:                |
    | 4.0.x   | :white_check_mark: |
    | < 4.0   | :x:                |

    ## Reporting a Vulnerability

    Use this section to tell people how to report a vulnerability.

    Tell them where to go, how often they can expect to get an update on a
    reported vulnerability, what to expect if the vulnerability is accepted or
    declined, etc.
  MD

  def initialize(repository)
    @repository = repository
  end

  def repository
    file&.repository
  end

  def default_branch
    repository&.default_branch
  end

  def path
    file&.path
  end

  def file
    return @file if defined? @file

    @file = @repository.preferred_security_policy
  rescue GitRPC::Error
    @file = nil
  end

  def exists?
    # Use nil? instead of present? since TreeEntry implements empty? and so
    # empty SECURITY.md files will return false when present? is called on them
    # and we want to know if they exist even if they are empty
    !file.nil?
  end
end
