# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class TrackingBlockErrorComponent < ApplicationComponent
    extend T::Sig

    attr_reader :error_type, :error_details

    sig do
      params(
        error_type: T.any(Symbol, String),
        is_precache: T::Boolean,
        error_details: T.nilable(T::Array[String])
      ).void
    end
    def initialize(error_type:, is_precache: false, error_details: nil)
      @error_type = error_type.to_sym
      @is_precache = is_precache
      @error_details = error_details
    end

    sig { returns(Symbol) }
    def banner_scheme
      case @error_type
      when :invalid_format,
        :invalid_items,
        :legacy_tasklist,
        :soft_limit_tasks_per_tasklist,
        :soft_limit_tasklists_per_issue
        :warning
      when :server_error,
        :sync_error,
        :hard_limit_tasks_per_tasklist,
        :hard_limit_tasklists_per_issue
        :danger
      else
        :warning
      end
    end

    sig { returns(String) }
    def error_message
      case @error_type
      when :invalid_format, :invalid_items
        <<~BODY
        We're having trouble rendering your tasklist, it's most likely has one of the following formatting errors:
        <ul>
          <li>indented tasks (i.e. nested tasklist; support for this is coming!)</li>
          <li>an empty task (i.e. <code>- [ ]</code> on a line by itself)</li>
          <li>any empty new lines (before/after the tasklist or in between tasks)</li>
          #{
            unless @is_precache
              "<li>duplicate issue/pr links</li>
              <li>a draft task exceeds 512 characters</li>"
            end
          }
        </ul>
        Please check the
        <a href=\"#{GitHub.help_url}/issues/managing-your-tasks-with-tasklists/creating-a-tasklist#creating-tasklists-with-markdown\"
          target=\"_blank\"
          rel=\"noopener noreferrer\"
        >
        tasklists documentation
        </a>
        for more information.  <a href=\"https://github.com/orgs/community/discussions/39106?sort=new\"
        target=\"_blank\"
        rel=\"noopener noreferrer\"> 🔗 Feedback Discussion </a> <br> <br>

        Thank you for participating in the Private Beta ❤️
        BODY
      when :server_error
        "An error occurred while loading your tasklist. Please try refreshing the page, or edit + save the issue body."
      when :sync_error
        "An error occurred while saving your changes. Please try editing and saving the issue description again."
      when :legacy_tasklist
        <<~BODY
        <p>Hello, early adopter!</p>

        <p>It looks like you are using the legacy tasklist format. Starting on the 30th of June will be discontinuing support for this format and <strong>your data may be lost.</strong> Don't fear, however. Change the contents of this tasklist in any way and we will convert you automatically.</p>

        Please check the
        <a href=\"#{GitHub.help_url}/issues/managing-your-tasks-with-tasklists/creating-a-tasklist#creating-tasklists-with-markdown\"
          target=\"_blank\"
          rel=\"noopener noreferrer\"
        >
        tasklists documentation
        </a>
        for more information.  <a href=\"https://github.com/orgs/community/discussions/39106?sort=new\"
        target=\"_blank\"
        rel=\"noopener noreferrer\"> 🔗 Feedback Discussion </a> <br> <br>

        <p>Thank you for participating in the Private Beta ❤️ </p>
        BODY
      when :soft_limit_tasks_per_tasklist,
        :soft_limit_tasklists_per_issue,
        :hard_limit_tasks_per_tasklist,
        :hard_limit_tasklists_per_issue
        <<~BODY
        <p>#{limit_message}</p>

        Please check the
        <a href=\"#{helpers.docs_url("issues/about-tasklists")}\"
          target=\"_blank\"
          rel=\"noopener noreferrer\"
        >
        tasklists documentation
        </a>
        for more information.  <a href=\"https://github.com/orgs/community/discussions/39106?sort=new\"
        target=\"_blank\"
        rel=\"noopener noreferrer\"> 🔗 Feedback Discussion </a> <br> <br>

        Thank you for participating in the Private Beta ❤️
        BODY
      else
        "An unknown problem occurred."
      end
    end

    private

    def limit_message
      case @error_type
      when :soft_limit_tasks_per_tasklist
        "We noticed your issue has over #{TasklistBlocks::Limiter::SOFT_LIMIT_TASKS_PER_TASKLIST} tasks in a tasklist, which can result in odd behavior with tasklists. We recommend splitting your tasks into another tasklist."
      when :soft_limit_tasklists_per_issue
        "We noticed your issue has over #{TasklistBlocks::Limiter::SOFT_LIMIT_TASKLISTS_PER_ISSUE} tasklists, which can result in odd behavior with tasklists. We recommend splitting your tasks into another issue."
      when :hard_limit_tasks_per_tasklist
        "There is a max of #{TasklistBlocks::Limiter::HARD_LIMIT_TASKS_PER_TASKLIST} tasks in a tasklist so we recommend splitting your tasks into another tasklist."
      when :hard_limit_tasklists_per_issue
        "There is a max of #{TasklistBlocks::Limiter::HARD_LIMIT_TASKLISTS_PER_ISSUE} tasklists in an issue so we recommend splitting your tasks into another issue."
      end
    end
  end
end
