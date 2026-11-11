# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module Diff
      SUMMARY_FIELDS = [:lines_added, :lines_deleted, :lines_changed, :summary].freeze

      class << self
        def for(head_repo_id:, base_repo_id:, start_ref_or_oid:, end_ref_or_oid:, timeout: nil,
                base_commit_oid: nil, algorithm: GitRPC::Diff::ALGORITHM_DEFAULT, use_summary:,
                compare_repo:, context_lines: {}, paths: [], pull_request: nil)

          async_base_repo = Platform::Loaders::ActiveRecord.load(::Repository, base_repo_id.to_i, security_violation_behaviour: :nil)
          async_base_repo.then do |base_repo|
            next if base_repo.nil?

            base_repo.async_network.then do
              Models::Diff.new(head_repo_id:     head_repo_id,
                               base_repo:        base_repo,
                               start_ref_or_oid: start_ref_or_oid,
                               end_ref_or_oid:   end_ref_or_oid,
                               base_commit_oid:  base_commit_oid,
                               algorithm:        algorithm,
                               use_summary:      use_summary,
                               timeout:          timeout,
                               compare_repo:     compare_repo,
                               context_lines:    context_lines,
                               paths:            paths,
                               pull_request:     pull_request)
            end
          end
        end

        # Public: Should a diff generated according to the provided irep nodes have use_summary set?
        #
        # selection - a Hash of field name Strings to internal representation of nodes,
        #             typically the scoped_children of the context's selection.
        #
        # Returns true if the diff or its patches request summary info.
        def use_summary?(lookahead)
          # Check for a summary field on the diff object
          lookahead.selections.each do |diff_field|
            if SUMMARY_FIELDS.include?(diff_field.name)
              return true
            end
          end

          # Check for summary fields on the patches
          patches_selection = lookahead.selection("patches")
          if node_fields_include?(patches_selection, SUMMARY_FIELDS)
            return true
          end
          # No summary fields were found
          false
        end

        # Public: Should the patches of the diff wrap GitRPC::Diff::Delta objects or GitHub::Diff::entry objects?
        #
        # Returns true if the diff should iterate over its entries for patches
        def use_entries?(lookahead)
          node_fields_include?(lookahead, [:text])
        end

        private

        # Based on the given lookahead, see if any of `fields`
        # were requested on itself or the nodes.
        def node_fields_include?(lookahead, fields)
          edges_node_lookahead = lookahead.selection("edges").selection("node")
          nodes_lookahead = lookahead.selection("nodes")
          [lookahead, edges_node_lookahead, nodes_lookahead].each do |node_lookahead|
            fields.each do |field|
              return true if node_lookahead.selects?(field)
            end
          end
          false
        end
      end
    end
  end
end
