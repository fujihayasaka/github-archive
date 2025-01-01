# typed: strict
# frozen_string_literal: true

module Dependabot
  class CommentService
    sig { params(pull_request: PullRequest, dependabot_user: User).void }
    def initialize(pull_request:, dependabot_user:)
      @pull_request = pull_request
      @dependabot_user = dependabot_user

      @disallowed_users = T.let([], T::Array[String])
      @disallowed_teams = T.let([], T::Array[String])
      @disallowed_assignees = T.let([], T::Array[T.untyped])
      @missing_milestone = T.let(false, T::Boolean)
      @missing_labels = T.let([], T::Array[String])
      @dependabot_can_not_assign = T.let(false, T::Boolean)
    end

    sig { returns(T::Array[String]) }
    attr_accessor :disallowed_users

    sig { returns(T::Array[String]) }
    attr_accessor :disallowed_teams

    sig { returns(T::Array[String]) }
    attr_accessor :disallowed_assignees

    sig { returns(T::Boolean) }
    attr_accessor :missing_milestone

    sig { returns(T::Array[String]) }
    attr_accessor :missing_labels

    sig { void }
    def post_comment_on_missing_data
      msg = [
        reviewer_title,
        disallowed_user_message,
        disallowed_team_message,
        disallowed_assignee_message,
        missing_milestone_message,
        missing_labels_message,
      ].reject { |s| s.empty? }.join("\n\n")

      if msg.present?
        msg += "\n\nPlease fix the above issues or remove invalid values from `dependabot.yml`."

        pull_request.issue&.comments&.create!(
          user: dependabot_user,
          body: msg,
        )
      end
    end

    sig { params(repository: Repository).void }
    def post_reviewers_deprecation_warning(repository:)
      return if GitHub.flipper[:dependabot_reviewers_removed].enabled?(repository)
      return unless GitHub.flipper[:dependabot_reviewers_deprecated].enabled?(repository)

      msg = <<~MESSAGE
      The `reviewers` field in the `dependabot.yml` file will be removed soon. Please use the code owners file to specify reviewers for Dependabot PRs. For more information, see [this blog post](https://github.blog/changelog/2025-04-29-dependabot-reviewers-configuration-option-being-replaced-by-code-owners/).
      MESSAGE
      pull_request.issue&.comments&.create!(
        user: dependabot_user,
        body: msg,
      )
    end

    private

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(User) }
    attr_reader :dependabot_user

    sig { returns(String) }
    def reviewer_title
      return "" if disallowed_users.blank? && disallowed_teams.blank?

      "### Reviewers"
    end

    sig { returns(String) }
    def disallowed_user_message
      return "" unless disallowed_users.present?

      disallowed_user_logins = disallowed_users.sort.map { |u| "`#{u}`" }.join(", ")
      "The following users could not be added as reviewers: #{disallowed_user_logins}. Either #{disallowed_users.size > 1 ? 'they do not exist or they do not have' : 'the username does not exist or it does not have'} the correct permissions to be added as a reviewer."
    end

    sig { returns(String) }
    def disallowed_team_message
      return "" unless disallowed_teams.present?

      disallowed_team_slugs = disallowed_teams.sort.map { |t| "`#{t}`" }.join(", ")
      "The following teams could not be added as reviewers: #{disallowed_team_slugs}. Either #{disallowed_teams.size > 1 ? 'they do not exist or they do not have' : 'the team does not exist or it does not have'} the correct permissions to be added as a reviewer."
    end

    sig { returns(String) }
    def disallowed_assignee_message
      return "" unless disallowed_assignees.present?

      <<~MESSAGE
      ### Assignees

      The following users could not be added as assignees: #{disallowed_assignees.sort.map { |u| "`#{u}`" }.join(", ")}. Either #{disallowed_assignees.size > 1 ? 'they do not exist or they do not have' : 'the username does not exist or it does not have'} the correct permissions to be added as an assignee.
      MESSAGE
    end

    sig { returns(String) }
    def missing_milestone_message
      return "" unless missing_milestone == true

      <<~MESSAGE
      ### Milestone

      The specified milestone could not be found on this repository. If you view a milestone, the final part of the page URL, after milestone, is the identifier. For example: `https://github.com/<org>/<repo>/milestone/3`.
      MESSAGE
    end

    sig { returns(String) }
    def missing_labels_message
      return "" unless missing_labels.present?

      <<~MESSAGE
      ### Labels

      The following labels could not be found: #{missing_labels.sort.map { |l| "`#{l}`" }.join(", ")}. Please create #{missing_labels.size > 1 ? 'them' : 'it'} before Dependabot can add #{missing_labels.size > 1 ? 'them' : 'it'} to a pull request.
      MESSAGE
    end
  end
end
