# typed: false
# frozen_string_literal: true

module TasklistBlocks
  class UrlExpander
    TRACKING_BLOCK_ANCHOR_REGEX = /#tasklist-block-(?<tracking_block_id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/
    TRACKING_BLOCK_URL_REGEX = %r<#{Regexp.escape(GitHub.url)}/#{GitHub::HTML::IssueMentionFilter::NWO}/issues/(\d+)#{TRACKING_BLOCK_ANCHOR_REGEX}\b>

    def self.enabled?(issue)
      return false unless issue.respond_to?(:repository)
      return false unless issue.is_a?(::Issue)

      GitHub.flipper[:tasklist_block].enabled?(issue.repository&.owner)
    end

    def self.expand(issue)
      new(issue).expand
    end

    def initialize(issue, repository: nil)
      @issue = issue
      @repository = repository || issue.repository
      @body = issue.body
    end

    def expand
      return @body if @body.nil?

      @body.gsub(TRACKING_BLOCK_URL_REGEX) do |url|
        matches = Regexp.last_match
        uuid = matches["tracking_block_id"]
        tasklist_block = remote_tasklist_blocks_by_id[uuid] if remote_tasklist_blocks_by_id

        if tasklist_block.nil?
          GitHub.dogstats.increment("issues.tasklists.edit.unfurl.missing")

          url
        else
          body = tasklist_block.issues.collect do |issue|
            if issue.state == TasklistBlocks::DraftIssueState::OPEN
              "- [ ] #{issue.title}"
            elsif issue.state == TasklistBlocks::DraftIssueState::CLOSED
              "- [x] #{issue.title}"
            else
              x = issue.state == "closed" ? "x" : " "
              "- [#{x}] #{issue.url}"
            end
          end
          GitHub.dogstats.increment("issues.tasklists.edit.unfurl", tags: ["result:success"])

          <<~MD
          ```[tasklist]
          ### #{tasklist_block.name}
          #{body.join("\n")}
          ```
          MD
        end
      end
    end

    private

    # Returns Hash { String => IssuesGraph::Proto::TrackingBlock }
    def remote_tasklist_blocks_by_id
      return unless remote_tasklist_blocks
      @remote_tasklist_blocks_by_id ||= remote_tasklist_blocks.index_by do |tasklist_block|
        tasklist_block.key.primaryKey.uuid
      end
    end

    # Returns Twirp::ClientResp
    def remote_tasklist_blocks
      @remote_tasklist_blocks ||= @issue.remote_tracking_blocks
    end
  end
end
