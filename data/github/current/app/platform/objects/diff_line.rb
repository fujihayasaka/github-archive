# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiffLine < Platform::Objects::Base
      description "Represents a line of a diff between two commits objects."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      field :type, Enums::DiffLineType, description: "Type of this line.", null: false

      field :text, String, description: "Plain text contents of this line.", null: false

      field :raw, String, description: "Plain text contents of this line without any formatting/prefixing.", null: false
      def raw
        # NOTE: Matching behavior for suggested comments
        # https://github.com/github/github/blob/755d7389f0285334529ab3c62dfbd6a9e3864dd1/app/components/comments/suggestion_button_component.rb#L34-L36
        return object[:text] if object[:type] == :hunk
        object[:text].to_s[1..-1]
      end

      field :html, String, description: "HTML formatted contents of this line.", null: false

      field :position, Integer, description: "Position of this line in the diff.", null: false

      field :left, Integer, description: "Left side line number.", null: true

      field :right, Integer, description: "Right side line number.", null: true

      field :blob_line_number, Integer, description: "The absolute blob line number in the left or right blob this line represents.", null: false

      field :is_missing_newline_at_end, Boolean, description: "Indicates whether this line is missing a newline character at the end.", method: :no_newline_at_end, null: false

      field :threads, Connections.define(Objects::PullRequestThread), description: "Comment threads that begin on this line.", connection: true, null: true

      def threads
        if object[:pull_request_comparison]
          # We do not need to call an async positioned threads method here.
          # When this field is resolved from a PullRequestDiffEntry, the PullRequest::Comparison is already loaded.
          threads = @object[:pull_request_comparison].positioned_threads_for(viewer: @context[:viewer], path: object[:path], position: object[:position])
          return ArrayWrapper.new((threads || []).map { |thread| Platform::Models::PullRequestThread.new(thread) })
        end

        if object[:diff]
          object[:diff].async_positioned_threads_for(viewer: @context[:viewer], path: object[:path], position: object[:position]).then do |threads|
            ArrayWrapper.new((threads || []).map { |thread| Platform::Models::PullRequestThread.new(thread) })
          end
        end
      end

      def self.scope_items(diff_lines, context)
        diff_lines.each { |diff_line| diff_line[:already_performed_authorization] = true }
      end

      def self.authorized?(diff_line, context)
        if diff_line[:already_performed_authorization]
          true
        else
          super(diff_line, context)
        end
      end
    end
  end
end
