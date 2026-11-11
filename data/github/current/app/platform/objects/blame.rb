# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Blame < Platform::Objects::Base
      description "Represents a Git blame."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      field :ranges, [Objects::BlameRange], description: "The list of ranges from a Git blame.", null: false

      def ranges
        begin
          ranges = @object.empty? ? [] : [LineRange.new(@object.first[2], [], @object.repository)]
          @object.each do |lineno, old_lineno, commit, text|
            if commit.oid != ranges.last.commit.oid
              ranges << LineRange.new(commit, [], @object.repository)
            end
            line = { lineno: lineno, old_lineno: old_lineno, commit: commit, text: text }
            ranges.last.lines << line
          end
          ranges
        # because the line numbers and the path that is used to filter the Blame comes from customer
        # input, we should guard against bad input causing the GitRPC command to fail and just return
        # an empty array in this scenario
        rescue GitRPC::CommandFailed
          []
        rescue SpokesAPI::ResourceExhausted
          raise Platform::Errors::RateLimited.new("Rate limited while fetching blame")
        end
      end
    end
  end
end
