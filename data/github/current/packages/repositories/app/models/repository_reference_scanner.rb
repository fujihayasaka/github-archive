# typed: true
# frozen_string_literal: true

# Defines a filter that identifies repository references inside a string
# Params:
#  - text: the text to be filtered
#  - viewer: the user making the request against whom the permissions for the repository refs are checked
class RepositoryReferenceScanner
  include GitHub::IssueReferenceResolution

  NWO = /(\w+(?:-\w+)*\/[.\w-]+(?!\/.))/

  attr_reader :references

  def initialize(text:, viewer:)
    @text = text.strip
    @viewer = viewer

    scan_for_references
  end

  private

  def scan_for_references
    @references = @text.scan(%r<#{Regexp.escape(GitHub.url)}/#{NWO}\b>)
    @references = @references.filter_map do |matches|
      next unless matches.length

      repository = find_repo(matches.first, nil)
      next unless repository&.readable_by?(@viewer)

      repository
    end
  end
end
