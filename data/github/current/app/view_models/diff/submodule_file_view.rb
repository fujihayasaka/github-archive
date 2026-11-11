# typed: true
# frozen_string_literal: true

module Diff
  class SubmoduleFileView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TreeHelper

    MAX_DIFF_STATS_FILES = 100

    attr_reader :repository, :diff_entry

    def submodule
      return @submodule if defined?(@submodule)
      return unless diff_entry.submodule?

      @submodule = repository.submodule(diff_entry.b_sha, diff_entry.path)
    end

    def submodule_path_link
      base_path = File.basename(diff_entry.path)
      helpers.link_to_if(submodule_url_linkable?, base_path, submodule&.linkable_url)
    end

    def submodule_url_linkable?
      submodule&.url_is_linkable?
    end

    def submodule_diff_linkable?
      return false unless submodule

      return false if diff_entry.added? && diff_entry.b_blob.nil?
      return false if diff_entry.deleted? && diff_entry.a_blob.nil?
      return false if diff_entry.a_blob.nil? && diff_entry.b_blob.nil?

      submodule.user && submodule.repo
    end

    def submodule_url
      return @submodule_url if defined?(@submodule_url)
      return unless submodule_diff_linkable?

      @submodule_url = urls.submodule_content_url(submodule, nil, false)
    end

    def submodule_repo
      return if submodule.nil? || submodule.user.nil? || submodule.repo.nil?

      nwo = "#{submodule.user}/#{submodule.repo}"
      return unless repo = Repository.nwo(nwo)
      return unless repo.permit?(current_user, :read)

      repo
    end

    def submodule_compare_url
      return unless submodule_url
      "#{submodule_url}/compare/#{diff_entry.a_blob}...#{diff_entry.b_blob}"
    end

    def render_submodule_diff_stats?
      submodule_diff_summary_available? &&
        submodule_diff_summary.changed_files < MAX_DIFF_STATS_FILES
    end

    def submodule_diff_summary_available?
      submodule_diff_summary && submodule_diff_summary.available?
    end

    def submodule_diff_summary
      return @submodule_diff_summary if defined?(@submodule_diff_summary)
      return unless submodule_repo
      return if diff_entry.a_blob.nil? || diff_entry_b_blob.nil?

      diff = GitHub::Diff.new(submodule_repo, diff_entry.a_blob, diff_entry.b_blob,
                              base_sha: diff_entry.a_blob)
      @submodule_diff_summary = diff.summary
    end

    def each_submodule_diff_summary_delta_view
      submodule_diff_summary.deltas.each do |delta|
        yield Diff::SummaryDeltaView.new(delta)
      end
    end

    delegate :a_blob, :b_blob, :added?, :deleted?, :path,
             to: :diff_entry, prefix: true

    def diff_entry_short_b_blob
      (diff_entry.b_blob || GitHub::NULL_OID)[0, 6]
    end

    def diff_entry_short_a_blob
      (diff_entry.a_blob || GitHub::NULL_OID)[0, 6]
    end
  end
end
