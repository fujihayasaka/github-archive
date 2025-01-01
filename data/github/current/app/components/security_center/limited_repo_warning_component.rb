# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class LimitedRepoWarningComponent < ApplicationComponent

    PERMISSIONS_DOC_HREF = T.let("#{GitHub.help_url(ghec_exclusive: true)}/code-security/security-overview/about-security-overview#permission-to-view-data-in-security-overview", String)

    sig { returns(T.untyped) }; attr_reader :system_arguments

    sig { params(system_arguments: T.untyped).void }
    def initialize(**system_arguments)
      @system_arguments = system_arguments
    end
  end
end
