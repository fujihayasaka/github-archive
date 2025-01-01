# typed: true
# frozen_string_literal: true

module GhostPilot
  class DiffSummaryComponent < BaseContextComponent

    erb_template <<-ERB
      <% if lazy_load %>
        <%= render GhostPilot::AsyncContextFragmentComponent.new(src: src) %>
      <% else %>
        <span hidden
          id="<%= element_id %>"
          data-description="Instructions for how the assistant would write an entire pull request description."
          data-value="<%= diff_prompt %>"></span>
      <% end %>
    ERB

    attr_reader :comparison, :repository, :lazy_load

    sig { params(comparison: T.nilable(GitHub::Comparison), lazy_load: T::Boolean).void }
    def initialize(comparison: nil, lazy_load: false)
      @comparison = comparison
      @lazy_load = lazy_load

      if lazy_load && @comparison.nil?
        raise ArgumentError, "comparison is required when lazy_load is true"
      end

      @repository ||= T.must(@comparison).repo
    end

    def range
      "#{comparison.base_ref}...#{comparison.head_ref}"
    end

    # This is effectively copy/pasted from
    #   packages/copilot4prs/app/lib/pull_requests/copilot/prompt/summary_pipeline.rb
    # It's the prompt used to generate complete summaries for PRs, but seems to generate good suggestions
    # when using it for autocompletion as well.
    def diff_prompt
      target = repository.fork? ? repository.parent || repository : repository
      owner = target.owner
      copilot_content_exclusion_rules = nil
      #  need to fetch the copilot content exclusion list
      if owner.is_a?(Organization) && ::Copilot::ContentExclusion.is_available?(owner)
        paths = ::Copilot::ContentExclusion.rules_for_repo(target).flat_map { |_config, rules| rules.collect(&:patterns).flatten.uniq }
        copilot_content_exclusion_rules = paths.map { |path| path[0] == "/" ? path[1..-1] : path }
      end

      filtered_diffs = begin
        PullRequests::Copilot::DiffsFilter.new(diffs: comparison.diffs, copilot_content_exclusion: copilot_content_exclusion_rules).to_a
      rescue GitRPC::InvalidFullOid => e
        return ""
      end

      return "" if filtered_diffs.blank?

      diff_hunks = PullRequests::Copilot::DiffHunk.diffs_to_hunks(filtered_diffs)
      overall_summary_prompt = GhostPilot::Prompt::Summary.prompts(diff_hunks:).first
      overall_summary_prompt&.render
    end

    def element_id
      "pull-request-diff"
    end

    def src
      ghost_pilot_diff_summary_path(repository: repository, user_id: repository.owner, range: range)
    end
  end
end
