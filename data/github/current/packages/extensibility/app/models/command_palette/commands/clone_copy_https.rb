# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class CloneCopyHttps < CopyableCommand
      scope_type "Repository", "Issue", "PullRequest", "Discussion"

      display_as "Copy Clone HTTP URL", icon: "copy"

      def enabled?
        repository.readable_by?(current_user) && !repository.ssh_certificate_requirement_enabled?
      end

      def copyable_text
        repository.http_url
      end

      def copyable_message
        "Clone URL copied!"
      end

      def repository
        if scoped_object.class.name == "Repository"
          scoped_object
        else
          scoped_object.repository
        end
      end
    end
  end
end
