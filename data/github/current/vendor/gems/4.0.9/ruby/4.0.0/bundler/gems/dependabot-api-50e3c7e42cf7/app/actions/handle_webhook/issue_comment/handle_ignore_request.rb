# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleIgnoreRequest
      def initialize(pull_request:, requester:, comment_body:, comment_id:)
        @pull_request = pull_request
        @requester = requester
        @comment_body = comment_body.downcase
        @comment_id = comment_id
      end

      def run
        return create_invalid_command_comment unless validate_command(@comment_body)
        return create_permissions_comment unless user_has_write_permissions?
        # Skip semver_req_on_multi_version_pr check if group_update flag is true
        return create_multi_dep_ignore_advice if !pull_request.grouped_update? && semver_req_on_multi_version_pr?
        return create_git_dep_ignore_advice if semver_req_on_git_pr?

        # Compute dependency name from a group update PR comment
        @dep_to_ignore = dep_name_if_group_update
        return unless find_or_create_ignore_condition

        handle_pull_request
      end

      private

      attr_reader :requester, :pull_request, :comment_body, :comment_id, :dep_to_ignore

      def validate_command(comment)
        # If the ignore command is not valid, a comment is created on the PR
        # to let the user know, and the method returns early
        regex = if pull_request.grouped_update? || pull_request.multiple_dependencies?
                  HandleWebhook::IssueComment::IGNORE_MULTIPLE_DEPS_VALIDATION_REGEX
                else
                  HandleWebhook::IssueComment::IGNORE_SINGLE_DEP_VALIDATION_REGEX
                end
        comment.match?(regex)
      end

      def create_invalid_command_comment
        valid_command_hint = if pull_request.grouped_update?
                               "For grouped and multi-dependency PRs, use commands like:\n" \
                                 "`@dependabot ignore <dependency name> major version`\n" \
                                 "`@dependabot ignore <dependency name> minor version`\n" \
                                 "`@dependabot ignore these dependencies`\n" \
                                 "`@dependabot ignore <dependency name>`"
                             else
                               "For single dependency PRs, use commands like:\n" \
                                 "`@dependabot ignore this major version`\n" \
                                 "`@dependabot ignore this minor version`\n" \
                                 "`@dependabot ignore this dependency`"
                             end

        msg = "Sorry, the command you entered is not valid for this pull request. " \
              "Please check the syntax and try again. \n\nValid commands:\n#{valid_command_hint}"

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def handle_pull_request
        # Close the PR if the updated_dependencies count in the group update PR is
        # just 1 after the dependency to ignore has been removed.
        if pull_request.grouped_update? && pull_request.updated_dependencies.count > 1
          recreate_and_create_version_ignore_comment
        else
          close_and_create_version_ignore_comment
        end
      end

      def semver_req_on_multi_version_pr?
        return false unless pull_request.multiple_dependencies?
        return false unless precision_for_ignore_req_from_comment != 1

        pull_request.updated_dependencies.map(&:version).uniq.count != 1
      end

      def semver_req_on_git_pr?
        return false unless precision_for_ignore_req_from_comment != 1

        pull_request.updated_dependencies.
          any? { |dep| dep.version.match?(/^[0-9a-f]{40}$/) }
      end

      def recreate_and_create_version_ignore_comment
        # Ignore condition is created which will be passed to the updater in core
        # to ignore the dependency and will close this existing PR and will
        # recreate a new PR with the ignored dependency removed.
        HandleRecreateRequestJob.perform_later(pull_request: pull_request)
        create_version_ignore_comment
      end

      def close_and_create_version_ignore_comment
        ClosePullRequest.new(pull_request: pull_request).run
        create_version_ignore_comment
      end

      def create_version_ignore_comment
        msg =
          if precision_for_ignore_req_from_comment == 1
            if pull_request.grouped_update?
              "OK, I won't notify you about #{dep_to_ignore} again, unless "\
              "you unignore it."
            elsif pull_request.multiple_dependencies?
              "OK, I won't notify you about any of these dependencies again, "\
              "unless you re-open this PR."
            else
              "OK, I won't notify you about "\
              "#{pull_request.updated_dependencies.first.name} again, unless "\
              "you re-open this PR."
            end
          else
            handle_update_with_precision_greater_than_one
          end

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def handle_update_with_precision_greater_than_one
        msg = "OK, I won't notify you about version #{ignored_version} "
        msg += if pull_request.grouped_update?
                 "of #{dep_to_ignore} again, unless you unignore it."
               else
                 "again, unless you re-open this PR."
               end
        msg
      end

      def ignored_version
        target_dependency =
          if pull_request.grouped_update?
            pull_request.updated_dependencies.find { |dep| dep.name.casecmp?(dep_to_ignore) }
          else
            pull_request.updated_dependencies.first
          end
        target_dependency.version.split(".").
          first(precision_for_ignore_req_from_comment - 1).
          fill("x", (precision_for_ignore_req_from_comment - 1)...3).
          join(".")
      end

      def find_or_create_ignore_condition
        FindOrCreateIgnoreCondition.new(
          pull_request: pull_request,
          precision_to_ignore: precision_for_ignore_req_from_comment,
          comment_id: comment_id,
          dep_name: dep_to_ignore,
        ).run
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def precision_for_ignore_req_from_comment
        if ignore_comment.include?("major") then 2
        elsif ignore_comment.include?("minor") then 3
        elsif ignore_comment.include?("patch") then 4
        elsif ignore_comment.include?("this") ||
              ignore_comment.include?("these") ||
              ignore_comment.include?("package") ||
              ignore_comment.include?("dependency") ||
              ignore_comment.include?("these dependencies") ||
              comment_body.split.length == 3 # ignore a specific dependency by name
          1
        else
          raise "Unexpected comment: #{ignore_comment}"
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def dep_name_if_group_update
        return nil unless pull_request.grouped_update?

        parts = comment_body.split
        return nil if parts.length < 3

        parts[2]
      end

      def ignore_comment
        @ignore_comment ||=
          comment_body.match(HandleWebhook::IssueComment::IGNORE_SINGLE_DEP_VALIDATION_REGEX)&.to_s ||
          comment_body.match(HandleWebhook::IssueComment::IGNORE_MULTIPLE_DEPS_VALIDATION_REGEX)&.to_s
      end

      def create_multi_dep_ignore_advice
        msg = "This option is only available on single-dependency pull "\
              "requests, as the versions in multi-dependency pull requests "\
              "may differ.\n\n"\
              "If you'd like to ignore all updates for these dependencies "\
              "just reply `@dependabot ignore these dependencies`."

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_git_dep_ignore_advice
        msg = "This option isn't available on git dependencies, as Dependabot "\
              "currently stores their SHA rather than their version.\n\n"\
              "If you'd like to ignore all updates for this dependency "\
              "just reply `@dependabot ignore this dependency`."

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_permissions_comment
        msg = "Sorry, only users with push access can use that command."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def user_has_write_permissions?
        @user_permission ||=
          RepoPermissionChecker.new(
            repo: pull_request.repo,
            user_github_login: requester,
          ).permission_level

        %w(write admin).include?(@user_permission)
      end
    end
  end
end
