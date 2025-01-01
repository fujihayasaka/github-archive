# typed: true
# frozen_string_literal: true

module GitAuth
  # Generate a list of notices to be displayed to the pushing user in the git CLI.
  class PushNotices
    def self.call(repo, data)
      new(repo: repo, data: data).call
    end

    # Contains the result of calling PushNotices and handles
    # serializing to a single string for display.
    class Result
      attr_reader :notices

      def initialize(notices)
        @notices = notices
      end

      def any?
        notices.any?
      end

      # Add a leading newline and two trailing to provide some visual offset in the CLI
      def for_display
        "\n#{notices.join("\n\n")}\n\n"
      end
    end

    attr_reader :repo, :data

    def initialize(repo:, data:)
      @repo = repo
      @data = data
    end

    def call
      Result.new([new_pr_notice, vulnerability_notice, branch_was_renamed_notice].select(&:present?))
    end

    def new_pr_notice
      return if data["ref_updates"].size != 1

      before = first_ref_update["before_oid"]
      if first_head_push?(before, qualified_ref_name) && !default_ref_push?
        notice = "Create a pull request for '#{short_ref_name}' on GitHub by visiting:\n     #{GitHub.url}/#{repo.name_with_display_owner}/pull/new/#{Api::LegacyEncode.encode(short_ref_name)}"
      end

      notice
    end

    def vulnerability_notice
      return if user.nil?
      return unless user.wants_vulnerability_cli_notifications?
      return unless repo.vulnerability_alerts_visible_to?(user)

      vuln_count = repo.open_vulnerability_alerts.count
      return if vuln_count.zero?

      return if ref_is_tag?(qualified_ref_name)

      GlobalInstrumenter.instrument("repository.push_vulnerability_notification", {
        repository: repo,
        actor: user,
      })

      counts_by_severity = repo.alert_count_by_severity(actor: user)
      vulnerabilities = "#{vuln_count} #{'vulnerability'.pluralize(vuln_count)}"
      vuln_breakdown = vuln_count_string(counts_by_severity)

      alerts_url =
        if vuln_count == 1
          repo.open_vulnerability_alerts.first&.permalink(include_host: true)
        else
          UrlHelpers.repository_alerts_url(
            host: GitHub.url,
            user_id: repo.owner,
            repository: repo,
          )
        end

      "GitHub found #{vulnerabilities} on #{repo.name_with_display_owner}'s default branch (#{vuln_breakdown}). To find out more, visit:\n     #{alerts_url}"
    end

    def branch_was_renamed_notice
      # create a notice string for each branch being created that has an associated rename record.
      # the user might not be aware that they are creating this branch or may have intended to update the renamed branch.
      # collect a list of all the ref updates which are creating branches.
      short_ref_names = data["ref_updates"].filter_map do |ru|
        refname = ru["refname"]
        next unless refname.start_with?("refs/heads/") # must be a branch
        next if ru["before_oid"] != GitHub::NULL_OID # nil before_oid means branch is being created (could be a real rename)
        next if ru["after_oid"] == GitHub::NULL_OID # nil after_oid means branch is being deleted
        refname.delete_prefix("refs/heads/")
      end
      return unless short_ref_names

      # for these branch creations, alert if a branch with this name was previously renamed to something else.
      repo.branch_renames.latest.finished.where(old_name: short_ref_names)
        .map { |r| "Heads up! The branch '#{r.old_name_for_display}' that you pushed to was renamed to '#{r.new_name_for_display}'." }
        .join("\n")
        .presence
    end

    private

    def user
      return @user if defined?(@user)
      @user = User.find_by(login: data["pusher"])
    end

    def first_ref_update
      @first_ref_update ||= data["ref_updates"].first
    end

    def short_ref_name
      @short_ref_name ||= qualified_ref_name.delete_prefix("refs/heads/")
    end

    def qualified_ref_name
      @qualified_ref_name ||= first_ref_update["refname"]
    end

    def first_head_push?(before_oid, current_ref)
      GitHub::NULL_OID == before_oid && current_ref.start_with?("refs/heads/")
    end

    def default_ref_push?
      return @default_ref_push if defined?(@default_ref_push)

      @default_ref_push = qualified_ref_name == default_ref_name || !repo.spokes_api.resolve_object(object_name: default_ref_name)
    end

    def default_ref_name
      @default_ref_name ||= "refs/heads/#{repo.default_branch}"
    end

    def ref_is_tag?(refname)
      refname.to_s.start_with?("refs/tags/")
    end

    def vuln_count_string(counts)
      sevs = Vulnerability::SEVERITIES.reverse
      count_strings = sevs.map do |severity|
        if counts[severity]
          "#{counts[severity]} #{severity}"
        end
      end

      count_strings.compact.join(", ")
    end

    def open_pull_request_number_for_ref
      repo.pull_requests.open_pulls.where(head_ref: Git::Ref.safe_ref_name(ref_names: qualified_ref_name), issues: { repository_id: repo.id }).limit(1).pluck(:number).first
    end
  end
end
