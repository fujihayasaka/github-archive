# typed: true
# frozen_string_literal: true

module Stafftools
  module Search
    class AuditLogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :logs
      attr_reader :query_string
      attr_reader :page
      attr_reader :current_user
      attr_reader :results

      # Keys in the security log that are valid stafftools search queries.
      LINKABLE_KEYS = %i[
        actor
        actor_id
        admins
        admin_ids
        deploy_key_fingerprint
        org
        org_id
        repo
        repo_id
        user
        user_id
        staff_actor
        staff_actor_id
        issue_id
        issue_comment_id
        pull_request_id
        review_id
        pull_request
        comment_id
        commit_comment_id
      ]

      # Keys in audit log that need special link generation
      STAFFTOOLS_LINKABLE_KEYS = %i[
        issue_id
        issue_comment_id
        pull_request_id
        review_id
        pull_request
        comment_id
        commit_comment_id
      ]

      ACTIONS_THAT_REQUIRE_PROMPT = %w[
        issue.update
        issue_comment.update
        issue_comment.destroy
      ]

      DEVICE_VERIFICATION_ACTIONS = %w[
        user.new_device_used
        user.device_verification_requested
        user.device_verification_success
        user.device_unverification
      ]

      MOBILE_REGISTRATION_REVOKE_ACTION = "mobile_device_public_key.create"

      def page_title
        "Audit log"
      end

      def page # rubocop:disable Lint/DuplicateMethods
        (@page || 1).to_i
      end

      def next_cursor
        if @results.respond_to?(:after_cursor)
          @results.after_cursor
        elsif FeatureFlag.vexi.enabled?(:audit_log_async_stafftools, @current_user, default: false)
          @results[:after]
        end
      end

      def prev_cursor
        if @results.respond_to?(:before_cursor)
          @results.before_cursor
        elsif FeatureFlag.vexi.enabled?(:audit_log_async_stafftools, @current_user, default: false)
          @results[:before]
        end
      end

      def prev_page?
        return !@results[:before].empty? if FeatureFlag.vexi.enabled?(:audit_log_async_stafftools, @current_user, default: false)

        if @results.respond_to?(:has_previous_page?)
          @results.has_previous_page?
        else
          page > 1
        end
      end

      def next_page?
        return !@results[:after].empty? if FeatureFlag.vexi.enabled?(:audit_log_async_stafftools, @current_user, default: false)

        # Driftwood::Results does not have next_page.present?
        if @results.respond_to?(:has_next_page?)
          @results.has_next_page?
        else
          @results.next_page.present?
        end
      end

      def prev_page_params
        page_params(page - 1, before: prev_cursor)
      end

      def next_page_params
        page_params(page + 1, after: next_cursor)
      end

      def start_async_query(after:, before:, query:)
        urls.stafftools_audit_log_query_start_path(after: after, before: before, query: query)
      end

      def logs?
        return false if logs.nil?
        logs.any?
      end

      def show_copy_all?
        !@query_string.blank? && logs?
      end

      def show_copy_filtered?
        !GitHub.enterprise? && show_copy_all?
      end

      def ade_query?
        !GitHub.enterprise?
      end

      def show_verify_device?(log)
        valid_action = GitHub.sign_in_analysis_enabled? &&
          log.user &&
          DEVICE_VERIFICATION_ACTIONS.include?(log.action)

        device = valid_action && log.user.authenticated_devices.find_by_device_id(log.device_cookie)
        valid_action && device && device.unverified?
      end

      def show_unverify_device?(log)
        valid_action = GitHub.sign_in_analysis_enabled? &&
          log.user &&
          DEVICE_VERIFICATION_ACTIONS.include?(log.action)

        device = valid_action && log.user.authenticated_devices.find_by_device_id(log.device_cookie)
        valid_action && device && device.verified?
      end

      def show_mobile_revoke?(log)
        return unless !GitHub.enterprise? && log.action == MOBILE_REGISTRATION_REVOKE_ACTION
        return unless log.data["public_key_type"] == "auth" # auth is the user facing registration event
        return unless log.actor_id && log.actor && log.data["oauth_access_id"] > 0 # valid data

        log.actor.has_mobile_device_auth_key?(log.data["oauth_access_id"])
      end

      def json_css
        "btn btn-sm tooltipped tooltipped-s"
      end

      def json_title
        "Download all query results (limit 5000) as unsanitized JSON"
      end

      def json_log_path
        urls.stafftools_audit_log_path query: query_string, format: :json
      end

      def filtered_logs
        logs.reject { |log| log.hidden_from_users? && log.hidden_from_orgs? }
      end

      def filtered_pretty_metadata
        metadata = filtered_logs.map { |log| Hash[log.sanitized_metadata] }
        JSON.pretty_generate metadata
      end

      def all_pretty_metadata
        metadata = logs.map { |log| Hash[log.sanitized_metadata] }
        JSON.pretty_generate metadata
      end

      def actor_location(log)
        if hostname = log.metadata[:console_host]
          hostname = $1 if hostname =~ /github-([^-]+)-/
          "a console on #{hostname}"
        else
          ip_dot log.actor_ip
        end
      end

      def ip_dot(ip)
        return "an unknown IP" if ip.blank?
        hash = Digest::SHA256.hexdigest(ip)
        helpers.content_tag :span, ip, :class => "ip-dot", "data-ip-dot" => "#{hash[0]}" # rubocop:disable Rails/ViewModelHTML
      end

      # Identifies security log keys that are linkable to stafftools queries.
      #
      # key - An audit log key.
      #
      # Returns true if the key should be linked as a search query and false
      # otherwise.
      def linkable_key?(key)
        LINKABLE_KEYS.include? key
      end

      def stafftools_linkable_key?(key)
        STAFFTOOLS_LINKABLE_KEYS.include? key
      end

      def log_query(query)
        helpers.link_to query, urls.stafftools_search_path(query: query),
                        target: "_blank"
      end

      # this will return a stafftools link to the repo if it can find it.
      # otherwise it will return a stafftools search link
      def stafftools_repo_link(repo_id)
        if repo_id.is_a?(String) || repo_id.is_a?(Numeric)
          repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            ::Repositories.domain.by_id(repo_id.to_i)
          else
            ::Repository.find_by(id: repo_id.to_i)
          end
          if repo
            return helpers.link_to repo_id.to_s, "/stafftools/repositories/#{repo.name_with_owner}"
          end
        end

        log_query(repo_id.to_s)
      end

      # this will return a stafftools link to the user if it can find it.
      # otherwise it will return a stafftools search link
      def stafftools_user_link(user_id)
        if user_id.is_a?(String) || user_id.is_a?(Numeric)
          user = ::User.find_by(id: user_id.to_i)
          if user
            return helpers.link_to user.id.to_s, "/stafftools/users/#{user}"
          end
        end

        log_query(user_id.to_s)
      end

      # this will return a stafftools link to the business if it can find it.
      # otherwise it will return a stafftools search link
      def stafftools_business_link(biz_id)
        if biz_id.is_a?(String) || biz_id.is_a?(Numeric)
          biz = ::Business.find_by(id: biz_id.to_i)
          if biz
            return helpers.link_to biz.id.to_s, "/stafftools/enterprises/#{biz}"
          end
        end

        log_query(biz_id.to_s)
      end

      def stafftools_link(key, value, action, comment_type = nil)
        begin
          case key
          when :issue_id
            issue = Issue.includes(:repository).find(value) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            helpers.link_to value, urls.gh_stafftools_repository_issue_path(issue)
          when :pull_request_id, :pull_request
            pr = PullRequest.includes(:repository).find(value)
            helpers.link_to value, urls.gh_stafftools_repository_pull_request_path(pr)
          when :issue_comment_id
            comment = IssueComment.includes(:repository, :issue).find(value) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            helpers.link_to value, urls.gh_stafftools_repository_issue_comment_path(comment)
          when :commit_comment_id
            comment = CommitComment.find(value)
            helpers.link_to value, urls.stafftools_commit_comment_path(comment)
          when :review_id, :comment_id
            if (action.split(".").first == "pull_request_review_comment") || (comment_type == "PullRequestReviewComment")
              review = PullRequestReviewComment.includes(:repository, :pull_request).find(value)
              helpers.link_to value, urls.gh_stafftools_repository_pull_request_review_comment_path(review)
            else
              case comment_type
              when "IssueComment"
                stafftools_link(:issue_comment_id, value, action)
              when "CommitComment"
                stafftools_link(:commit_comment_id, value, action)
              else
                value
              end
            end
          else
            value
          end
        rescue ActiveRecord::RecordNotFound, ActionController::UrlGenerationError, NoMethodError
          # UrlGenerationError and NoMethodError can both be thrown when an object necessary for link generation
          # (like a repo or an org) has been deleted
          value
        end
      end

      def field_query(field_name, field_detail)
        field_name = field_name.to_s
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            webevents
            | where data.#{field_name} == "#{field_detail}"
          KQL
        else
          %Q|data.#{field_name}:"#{field_detail}"|
        end
      end

      def show_filter_links?
        if GitHub.driftwood_ade_queries_enabled?
          query_string !~ /action\s*==/
        else
          query_string !~ /[\s(]action:/
        end
      end

      def filter_action_query(action)
        new_query =
          if GitHub.driftwood_ade_queries_enabled?
            if query_string.blank?
              <<~KQL
                webevents
                | where action == "#{action}"
              KQL
            else
              <<~KQL
                #{cleaned_query_string.strip}
                | where action == "#{action}"
              KQL
            end
          else
            "#{cleaned_query_string} action:#{action}"
          end

        urls.stafftools_audit_log_path(query: new_query)
      end

      def hide_action_query(action)
        new_query =
          if GitHub.driftwood_ade_queries_enabled?
            if query_string.blank?
              <<~KQL
                webevents
                | where action != "#{action}"
              KQL
            else
              <<~KQL
                #{query_string.strip}
                | where action != "#{action}"
              KQL
            end
          else
            "#{query_string} -action:#{action}"
          end

        urls.stafftools_audit_log_path(query: new_query)
      end

      def invalid_tooltip_label(log)
        "Marked invalid by @#{log.marked_invalid_by} " \
        "for \"#{log.marked_invalid_for}\". " \
        "Invalid entries will not be shown to users."
      end

      def protected_repo?(repo_id)
        repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          ::Repositories.domain.by_id(repo_id)
        else
          ::Repository.find_by(id: repo_id)
        end
        repository&.private? && repository.owner&.login == "github"
      end

      def prompt_for_hubber_access?(actor, repo_id, action, privacy)
        return false unless GitHub.hubber_access_prompt_enabled?
        return false unless ACTIONS_THAT_REQUIRE_PROMPT.include?(action)
        return false unless @current_user

        actor ||= (::User.find_by_login(actor) || ::User.ghost)
        return false unless actor.employee? || protected_repo?(repo_id)
        return false if @current_user == actor
        !@current_user.hubber_access_reason_provided?(actor)
      end

      private

      def page_params(page, after: "", before: "")
        paramstring = "?"
        if after.blank? && before.blank?
          paramstring += "page=#{page}"
        else
          paramstring += "after=#{after}" unless after.blank?
          paramstring += "before=#{before}" unless before.blank?
        end
        paramstring += "&query=#{ERB::Util.url_encode(query_string)}" unless query_string.blank?
        paramstring
      end

      def cleaned_query_string
        return "" if query_string.blank?

        @cleaned_query_string ||=
          if GitHub.driftwood_ade_queries_enabled?
            query_string.gsub(/\|\s+(where|and|or)\s+action\s*!=.*['"]/, "")
          else
            query_string.gsub(/ \-action:[\w\.]+/, "")
          end
      end
    end
  end
end
