# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class GitSSHRemote < Platform::Scalars::Base
      description "Git SSH string"

      # GitSSHRemote is needed because repository.ssh_url does not return
      # an URI compliant string as we strip ssh://. With ssh:// left intact
      # we could use the URI scalar as Addressable would parse that correctly.
      # As it is now we would get InvalidURIError due to missing the URI scheme.
    end
  end
end
