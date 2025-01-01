# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module Prompt
      module DiffHunkEncoder
        include ActionView::Helpers::TagHelper
        include ::UrlHelper

        extend T::Helpers
        extend T::Sig

        abstract!

        sig { abstract.returns(T.nilable(PullRequest)) }
        def pull_request
        end

        sig { params(diff_hunk: DiffHunk).returns(String) }
        def self.encode(diff_hunk)
          blob_oid = diff_hunk.entry.b_blob || diff_hunk.entry.a_blob
          l, r = diff_hunk.left, diff_hunk.right

          encoded = "F#{blob_oid.first(7)}"
          encoded += "L#{l}" if l > 0
          encoded += "R#{r}" if r > 0
          encoded
        end

        sig { params(diff_hunk: DiffHunk).returns(String) }
        def encode_item(diff_hunk)
          DiffHunkEncoder.encode(diff_hunk)
        end

        sig { params(diff_hunk: DiffHunk).returns(String) }
        def expand_item(diff_hunk)
          non_context_lines = diff_hunk.lines.select { |l| l.addition? || l.deletion? }
          first, last = T.must(non_context_lines.first), T.must(non_context_lines.last)

          line_range = "#{first.deletion? ? "L" : "R"}#{first.current}"
          if first != last
            line_range += "-#{last.deletion? ? "L" : "R"}#{last.current}"
          end

          href = if pull_request
            "#{T.must(pull_request).permalink}/files"
          else
            "diffhunk://"
          end

          anchor = "##{diff_path_anchor(diff_hunk.entry.path)}"
          anchor += line_range
          href += anchor

          content = diff_hunk.entry.path
          content += line_range

          "[#{content}](#{href})"
        end
      end
    end
  end
end
