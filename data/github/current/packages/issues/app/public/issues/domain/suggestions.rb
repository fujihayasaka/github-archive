# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Suggestions < GH::Domain::Base
      FEEDBACK_URL = "https://forms.cloud.microsoft/r/P9bsiUn167"

      class TriageSuggestions < T::Struct
        # The suggestion body to post as a comment (required)
        const :body, String

        # Label names to apply to the issue
        const :labels, T::Array[String], default: []

        # Issue type name to set
        const :type, T.nilable(String), default: nil

        # Issue field values to set, each with :name and :value keys
        const :fields, T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]], default: []
      end

      # Applies AI-generated suggestions to an issue by posting a comment and
      # setting metadata (labels, type, fields).
      #
      # @param issue [Issue] The issue to apply suggestions to
      # @param suggestions [TriageSuggestions] The suggestions to apply
      # @param retriage [Boolean] Whether this is a retriage operation that should override existing metadata
      # @param skip_comment [Boolean] When true, skips posting the triage comment (only applies metadata)
      #
      # @return [GH::Result] Ok with IssueComment on success, Error if validation fails
      sig do
        params(
          issue: Issue,
          suggestions: TriageSuggestions,
          retriage: T::Boolean,
          skip_comment: T::Boolean
        ).returns(GH::Result[T.nilable(IssueComment)])
      end
      def suggest(issue:, suggestions:, retriage: false, skip_comment: false) # rubocop:disable Metrics/MethodLength
        # Validate that the issue is not a pull request
        return GH::Result::Error.new("suggestions cannot be applied to pull requests") if issue.pull_request?

        # Validate that body is present (only when posting a comment)
        body = suggestions.body
        unless skip_comment
          return GH::Result::Error.new("body is required") if body.blank?
        end

        # Get the Copilot bot user
        copilot_bot = T.let(get_copilot_bot, T.nilable(User))

        if !copilot_bot && IssuesTriageAgentFeature.fake_triage_enabled?
          copilot_bot = issue.user
        end

        unless copilot_bot
          GitHub.logger.warn("suggestions.no_copilot_bot", {
            "code.namespace" => "Issues::Domain::Suggestions",
            "issue_id" => issue.id
          })
          return GH::Result::Error.new("Copilot bot user not found")
        end

        # Set the Copilot bot as the modifying user for timeline events
        issue.modifying_user = copilot_bot

        comment = T.let(nil, T.nilable(IssueComment))

        # Push actor context so after_commit callbacks use the Copilot bot as actor
        GitHub.context.push(actor_id: copilot_bot.id) do
          Issue.transaction do
            unless skip_comment
              # Sanitize @mentions to avoid unwanted notifications, preserving the issue author's mention
              sanitized_body = sanitize_mentions(body, allowed_login: issue.user&.display_login)

              # Append the triage agent footer
              body_with_footer = append_footer(sanitized_body)

              # Post a comment with the suggestion body
              comment = issue.comments.create!(user: copilot_bot, body: body_with_footer)
            end

            # Apply labels if provided
            if suggestions.labels.any?
              apply_labels(issue: issue, label_names: suggestions.labels)
            end

            # Set issue type if provided (only if issue doesn't already have a type, unless retriage)
            if suggestions.type.present? && (retriage || issue.issue_type_id.nil?)
              set_issue_type(issue: issue, type_name: T.must(suggestions.type))
            end

            # Apply issue fields if provided, only single select fields are supported
            if suggestions.fields.any?
              apply_issue_fields(issue: issue, fields: suggestions.fields, actor: copilot_bot, retriage: retriage)
            end

            # Remove eyes emoji reaction to indicate triage is complete
            Issues.domain.reactions.remove_eyes(subject: issue, user_ids: [copilot_bot.id])
          end
        end

        if skip_comment
          GH::Result::Ok.new(nil)
        else
          GH::Result::Ok.new(T.must(comment))
        end
      rescue ActiveRecord::RecordInvalid => e
        GH::Result::Error::Validation.new(e.record, message: "Failed to apply suggestions: #{e.message}")
      rescue ActiveRecord::ActiveRecordError => e
        GH::Result::Error.new("Failed to apply suggestions: #{e.message}")
      end

      private

      # Appends the Copilot Triage Agent footer to the comment body
      # Checks if footer already exists to prevent duplication
      sig { params(text: String).returns(String) }
      def append_footer(text)
        return text if text.include?(Issues::Domain::Triage::TRIAGE_AGENT_FOOTER_BASE_TEXT)

        footer = "\n\n> #{Issues::Domain::Triage::TRIAGE_AGENT_FOOTER_BASE_TEXT} \u00b7 [Give feedback](#{FEEDBACK_URL})"
        "#{text}#{footer}"
      end

      # Sanitizes @mentions in text by wrapping them in backticks (inline code)
      # to prevent GitHub from resolving them as actual mentions and sending
      # notifications. Mentions of the allowed_login (typically the issue author)
      # are preserved so the triage agent can address them directly.
      #
      # Handles both individual @user mentions (via MentionFilter::MentionPattern)
      # and team @org/team mentions (via TeamMentionFilter::MentionPattern).
      sig { params(text: String, allowed_login: T.nilable(String)).returns(String) }
      def sanitize_mentions(text, allowed_login: nil)
        # First sanitize team mentions (@org/team), then individual mentions (@user).
        # Order matters: team mentions include a slash which individual mentions skip.
        result = sanitize_team_mentions(text)
        sanitize_user_mentions(result, allowed_login: allowed_login)
      end

      sig { params(text: String).returns(String) }
      def sanitize_team_mentions(text)
        text.gsub(GitHub::HTML::TeamMentionFilter::MentionPattern) do |match|
          org = T.must(Regexp.last_match(1))
          team = T.must(Regexp.last_match(2))
          prefix = match[/\A(.?)@/m, 1] || ""
          "#{prefix}`@#{org}/#{team}`" # rubocop:disable GitHub/DoNotAllowLogin -- org is from regex, not a model attribute
        end.gsub(GitHub::HTML::TeamMentionFilter::BusinessTeamMentionSanitizationPattern) do |match|
          team = T.must(Regexp.last_match(1))
          prefix = match[/\A(.?)@/m, 1] || ""
          "#{prefix}`@/#{team}`"
        end
      end

      sig { params(text: String, allowed_login: T.nilable(String)).returns(String) }
      def sanitize_user_mentions(text, allowed_login:)
        text.gsub(GitHub::HTML::MentionFilter::MentionPattern) do |match|
          username = T.must(Regexp.last_match(1))
          if allowed_login && username.downcase == allowed_login.downcase
            match # preserve the issue author's mention
          else
            prefix = match[/\A(.?)@/m, 1] || ""
            "#{prefix}`@#{username}`"
          end
        end
      end

      # Gets the Copilot bot user
      sig { returns(T.nilable(Bot)) }
      def get_copilot_bot
        app = T.let(Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
        app&.bot
      end

      # Applies labels to an issue, ignoring labels that don't exist in the repository
      sig { params(issue: Issue, label_names: T::Array[String]).void }
      def apply_labels(issue:, label_names:) # rubocop:disable Metrics/MethodLength
        return if label_names.empty?

        repository = T.must(issue.repository)
        existing_labels = ::Label.where(repository_id: repository.id)
          .with_name(label_names)
          .to_a

        # Warn about non-existent labels
        existing_label_names = existing_labels.map(&:name).map(&:downcase)
        label_names.each do |label_name|
          unless existing_label_names.include?(label_name.downcase)
            GitHub.logger.warn("suggestions.label_not_found", {
              "code.namespace" => "Issues::Domain::Suggestions",
              "issue_id" => issue.id,
              "repository_id" => repository.id,
              "label_name" => label_name
            })
          end
        end

        # Apply only the labels that exist
        if existing_labels.any?
          issue.add_labels(existing_labels)
        end
      end

      # Sets the issue type, ignoring invalid types
      sig { params(issue: Issue, type_name: String).void }
      def set_issue_type(issue:, type_name:) # rubocop:disable Metrics/MethodLength
        return if type_name.blank?

        repository = T.must(issue.repository)
        owner = repository.owner
        return unless owner&.organization?

        org_owner = T.cast(owner, Organization)

        # Find the issue type by name (case-insensitive)
        issue_type = Issues.domain.issue_types.by_organization_and_name(org_owner, type_name)

        if issue_type
          issue.issue_type = T.cast(issue_type, IssueType)
          issue.save!
        else
          GitHub.logger.warn("suggestions.issue_type_not_found", {
            "code.namespace" => "Issues::Domain::Suggestions",
            "issue_id" => issue.id,
            "repository_id" => repository.id,
            "owner_id" => owner.id,
            "type_name" => type_name
          })
        end
      end

      # Builds and applies single select issue fields
      sig do
        params(
          issue: Issue,
          fields: T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]],
          actor: User,
          retriage: T::Boolean
        ).void
      end
      def apply_issue_fields(issue:, fields:, actor:, retriage: false)
        field_attributes = build_single_select_field_attributes(issue: issue, fields: fields, retriage: retriage)
        return if field_attributes.empty?

        result = ::IssueFields::Builder.build_issue_field_values(
          issue: issue,
          actor: actor,
          attributes: field_attributes
        )

        case result
        when GH::Result::Ok
          result.value.each(&:save!)
        when GH::Result::Error
          GitHub.logger.warn("suggestions.issue_fields_update_failed", {
            "code.namespace" => "Issues::Domain::Suggestions",
            "issue_id" => issue.id,
            "error" => result.message
          })
        end
      end

      # Builds issue field attributes from field suggestions
      sig do
        params(
          issue: Issue,
          fields: T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]],
          retriage: T::Boolean
        ).returns(T::Array[Issues::IssueFieldSingleSelectValueAttributes])
      end
      def build_single_select_field_attributes(issue:, fields:, retriage: false)
        repository = T.must(issue.repository)
        owner = repository.owner
        return [] unless owner&.organization? && IssueFieldsFeature.enabled?(owner, context: nil)

        fields.filter_map do |field_suggestion|
          # Only single select fields are supported
          build_single_select_field_value_attributes(issue: issue, field_suggestion: field_suggestion, retriage: retriage)
        end
      end

      sig do
        params(
          issue: Issue,
          field_suggestion: T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))],
          retriage: T::Boolean
        ).returns(T.nilable(Issues::IssueFieldSingleSelectValueAttributes))
      end
      def build_single_select_field_value_attributes(issue:, field_suggestion:, retriage: false) # rubocop:disable Metrics/MethodLength
        field_name = field_suggestion[:name]
        field_value = field_suggestion[:value]
        return nil if field_name.blank? || field_value.blank?

        repository = T.must(issue.repository)

        # Find the single_select issue field by name_slug (parameterized name)
        field_name_slug = field_name.to_s.parameterize
        issue_field = IssueFieldSingleSelect.find_by(name_slug: field_name_slug, owner: repository.owner)

        if issue_field.nil?
          GitHub.logger.warn("suggestions.issue_field_not_found", {
            "code.namespace" => "Issues::Domain::Suggestions",
            "issue_id" => issue.id,
            "owner_id" => repository.owner_id,
            "field_name" => field_name
          })
          return nil
        end

        # Skip if the issue already has a value for this field (unless retriage)
        existing_value = IssueFieldValue.find_by(issue: issue, issue_field: issue_field, repository_id: issue.repository_id)
        return nil if existing_value && !retriage

        field_id = issue_field.id
        option = issue_field.options.find { |o| o.name.downcase == field_value.to_s.downcase }

        if option
          Issues::IssueFieldSingleSelectValueAttributes.new(field_id: field_id, option_id: option.id)
        else
          GitHub.logger.warn("suggestions.issue_field_option_not_found", {
            "code.namespace" => "Issues::Domain::Suggestions",
            "issue_id" => issue.id,
            "field_name" => issue_field.name,
            "option_value" => field_value
          })
          nil
        end
      end
    end
  end
end
