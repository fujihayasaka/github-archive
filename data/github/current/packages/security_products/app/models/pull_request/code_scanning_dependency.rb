# typed: true
# frozen_string_literal: true

class PullRequest
  module CodeScanningDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { PullRequest }

    included do
      T.bind(self, T.class_of(PullRequest))
      has_many :code_scanning_review_comments, -> (pr) { where(repository_id: pr.repository_id) }
      destroy_dependents_in_background :code_scanning_review_comments
    end

    def can_dismiss_code_scanning_suggested_fix?(user)
      can_apply_code_scanning_suggested_fix?(user)
    end

    def can_apply_code_scanning_suggested_fix?(user)
      # This is copied from PullRequests::CommentSuggestedChangesActionsComponent#viewer_can_apply_suggestion? as we want similar semantics.
      # As an added bonus #suggested_change_applicable_by? memoizes the result per user on the PR object.
      suggested_change_applicable_by?(user) && head_repository && head_ref
    end

    def code_scanning_latest_check_suite
      return @code_scanning_latest_check_suite if defined?(@code_scanning_latest_check_suite)

      integration = Apps::Internal.integration(:code_scanning)
      return @code_scanning_latest_check_suite = nil if integration.nil?

      sorted_oids = self.changed_commit_oids.reverse
      batch_size = 10

      check_suite = sorted_oids
        .in_groups_of(batch_size)
        .lazy.filter_map do |sorted_oid_batch|
          field_clause_for_sql = sorted_oid_batch.map { |oid| "'#{oid}'" }.join(",")
          T.must(repository).check_suites
            .where(head_sha: sorted_oid_batch)
            .where(status: CheckSuite.statuses[:completed])
            .where(github_app_id: integration.id)
            .order(Arel.sql("field(head_sha, #{field_clause_for_sql})"))
            .first
        end.first

      @code_scanning_latest_check_suite = check_suite.nil? ? nil : CodeScanningCheckSuite.find_by(check_suite: check_suite, repository: repository)
      if @code_scanning_latest_check_suite.nil?
        GitHub.logger.info(
          "No code scanning check suite found",
          "code.function" =>  "code_scanning_latest_check_suite",
          "gh.repo.id" => self.repository_id,
          "gh.pull_request.id" => self.id,
          "git.commit.oids" => sorted_oids,
        )
      end
      @code_scanning_latest_check_suite
    end

    def code_scanning_alert_for_review_comment(review_comment)
      alert_number = code_scanning_review_comment_for_comment(review_comment.id)&.alert_number
      return nil unless alert_number.present?
      async_code_scanning_alerts_cached!.sync&.find { |r| r.result.number == alert_number }
    end

    def code_scanning_review_comment_for_comment(comment_id)
      unless defined?(@code_scanning_review_comments_map)
        @code_scanning_review_comments_map = code_scanning_review_comments.to_a.index_by(&:pull_request_review_comment_id)
      end
      @code_scanning_review_comments_map[comment_id]
    end

    NonPreloadedAlerts = Class.new(StandardError)
    NonPreloadedSuggestedFixes = Class.new(StandardError)

    def async_code_scanning_alerts_cached!
      if @code_scanning_alerts_cached.nil?
        e = NonPreloadedAlerts.new("async_code_scanning_alerts_cached: alerts not loaded in memory for the pull_request. This could lead to N+1s.")
        e.set_backtrace(caller)
        raise(e) unless Rails.env.production?
        Failbot.report(e)
        @code_scanning_alerts_cached = async_code_scanning_alerts
      end
      @code_scanning_alerts_cached
    end

    def async_code_scanning_suggested_fixes_cached!
      if @code_scanning_suggested_fixes_cached.nil?
        e = NonPreloadedSuggestedFixes.new("async_code_scanning_suggested_fixes_cached: alerts fixes not loaded in memory for the pull_request. This could lead to N+1s.")
        e.set_backtrace(caller)
        raise(e) unless Rails.env.production?
        Failbot.report(e)
        @code_scanning_suggested_fixes_cached = async_code_scanning_suggested_fixes
      end
      @code_scanning_suggested_fixes_cached
    end

    def async_preload_code_scanning_alerts
      @code_scanning_alerts_cached ||= async_code_scanning_alerts
    end

    def async_preload_code_scanning_suggested_fixes
      @code_scanning_suggested_fixes_cached ||= async_code_scanning_suggested_fixes
    end

    def code_scanning_suggested_fix_alert(alert_number)
      return nil unless alert_number.present?
      async_code_scanning_suggested_fixes_cached!.sync.suggested_fix_alerts&.[](alert_number)
    end

    def pull_request_has_suggested_fixes?
      resp = async_preload_code_scanning_suggested_fixes.sync
      return false if resp.nil?
      resp.suggested_fix_alerts.length > 0
    end

    def ref_names
      [merge_ref.sub("merge", "head"), "refs/heads/" + head_ref.dup.force_encoding("utf-8").scrub!]
    end

    def build_ref_names_bytes_for_code_scanning_suggested_fix
      # include both refs/pull/xyz/merge and refs/pull/xyz/head along with the branch ref
      refs_bytes = code_scanning_latest_check_suite&.refs_bytes || []
      refs_bytes << merge_ref.b if merge_ref.starts_with?("refs/pull/")
      refs_bytes << merge_ref.sub("merge", "head").b if merge_ref.starts_with?("refs/pull/")
      refs_bytes
    end

    private

    def async_code_scanning_alerts
      # in the case where we have no code scanning review comments we can't find any alert numbers
      # to load from turboscan, therefore don't try to call it.
      return Promise.resolve([]) if alert_numbers.empty?

      cscs = code_scanning_latest_check_suite
      if cscs.nil?
        GitHub.dogstats.increment("code_scanning.pull_request.latest_code_scanning_checksuite", tags: ["found:false"])
        return Promise.resolve(nil)
      end

      GitHub.dogstats.increment("code_scanning.pull_request.latest_code_scanning_checksuite", tags: ["found:true"])
      GitHub::Turboscan.async_annotations(
        head_commit_oid: cscs.check_suite&.head_sha,
        numbers: alert_numbers,
        repository_id: repository_id,
        merge_commit_oid: cscs.pull_request_sha.presence,
      ).then do |r|
        if r&.error.present?
          GitHub.logger.error(
            r&.error,
            "code.function" => "async_annotations",
            "gh.repo.id" => repository_id,
            "gh.pull_request.id" => id,
            "gh.code_scanning.alert_numbers" => alert_numbers,
            "gh.pull_request.head_sha" => cscs.check_suite&.head_sha,
            "gh.pull_request.merge_commit_sha" => cscs.pull_request_sha.presence,
          )
        end
        r&.data&.results
      end
    end

    def async_code_scanning_suggested_fixes
      if repository.nil? || !CodeScanning::Autofix.enabled_for_repo?(repository)
        return Promise.resolve(empty_suggested_fix_response)
      end

      head_commit_oid = current_head_oid || head_sha
      ref_names_bytes = build_ref_names_bytes_for_code_scanning_suggested_fix

      if alert_numbers.empty? || head_commit_oid.blank? || ref_names_bytes.blank?
        return Promise.resolve(empty_suggested_fix_response)
      end

      GitHub::Turboscan::SuggestedFixes.async_suggested_fix(
        repository_id: self.repository_id,
        alert_numbers: alert_numbers,
        head_commit_oid:,
        ref_names_bytes:,
      ).then do |response|
        if response&.error.present?
          GitHub.logger.error(
            response&.error,
            "code.function" => "async_suggested_fix",
            "gh.repo.id" => self.repository_id,
            "gh.pull_request.id" => self.id,
            "gh.code_scanning.alert_numbers" => alert_numbers,
            "gh.pull_request.head_sha" => current_head_oid
          )
        end
        response&.data || empty_suggested_fix_response
      end
    end

    def empty_suggested_fix_response
      Turboscan::Proto::GetSuggestedFixResponse.new
    end

    def alert_numbers
      @alert_numbers ||= self.code_scanning_review_comments.map(&:alert_number).uniq
    end
  end
end
