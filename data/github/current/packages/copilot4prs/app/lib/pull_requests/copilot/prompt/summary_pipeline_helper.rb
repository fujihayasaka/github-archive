# typed: strict
# frozen_string_literal: true
module PullRequests
  module Copilot
    module Prompt
      module SummaryPipelineHelper
        include Kernel # so that puts works in #log method

        DIFF_HUNK_LINK_PATTERN = /(?<diffhunk_link>\[(?<link_text>[^,"\]]+)\]\(diffhunk:\/\/[^,"`\)]+\))/
        SINGLE_FILE_NAME_AT_START_OF_CODE_CHANGE_PATTERN = /[*-]\s(?<file_name_reference>`[^,"`]+`)\:/

        # Diffhunk links are long and can take up a lot of space in the PR summary. This method scans through a
        # completion string and simplifies these diffhunk links in two ways:
        #
        # 1. When there is a single file name at the start of a change description line, transform that name into a
        #    diffhunk link with the file name as the link text.
        # 2. If there is more than one diffhunk link in a change description, summarize the extra links at the end
        #    using a `[1] [2] [3]` format to make the change line more readable for users.
        sig { params(completion: String).returns(String) }
        def simplify_diffhunk_links(completion)
          completion.split("\n").each do |completion_line|
            matches = completion_line.to_enum(:scan, DIFF_HUNK_LINK_PATTERN).map { Regexp.last_match }

            # iterate over the matches in this line and replace them one at a time
            updated_completion_line = completion_line.dup
            matches.each_with_index do |match, index|
              next unless match && match[:diffhunk_link] && match[:link_text]

              # if there is only one file name at the start of the line, make that a link to the first file reference
              if index.zero? && updated_completion_line.match?(SINGLE_FILE_NAME_AT_START_OF_CODE_CHANGE_PATTERN)
                file_name_reference = T.must(updated_completion_line.match(SINGLE_FILE_NAME_AT_START_OF_CODE_CHANGE_PATTERN))[:file_name_reference]
                updated_completion_line = updated_completion_line.sub(
                  T.must(file_name_reference),
                  T.must(match[:diffhunk_link]).sub(T.must(match[:link_text]), T.must(file_name_reference))
                )
              end

              # if there's only one match on this line, clean up the reference link at the end of the line
              if matches.size == 1
                updated_completion_line = updated_completion_line.sub(" (#{T.must(match[:diffhunk_link])})", "")
                next
              end

              # if there's more  than one match, replace the long links at the end of the change line with the new, shorter links
              new_link = T.must(match[:diffhunk_link]).sub(T.must(match[:link_text]), "[#{index + 1}]")
              updated_completion_line = updated_completion_line
                .sub(T.must(match[:diffhunk_link]), new_link)
                .sub("(#{new_link}", new_link).sub("#{new_link})", new_link) # remove parenthesis around diffhunk links
                .sub("#{new_link},", new_link) # remove commas after diffhunk links
            end

            # replace the old line with the updated line which now includes shorter link text for all references
            completion = completion.sub(completion_line, updated_completion_line)
          end

          completion
        end
      end
    end
  end
end
