# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssue < Platform::Mutations::Base
      docs_category :issues
      include Platform::Helpers::ReadFromSelectedReplicas
      include Helpers::Agentic
      include Helpers::IssueSuggestions

      description "Updates an Issue."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The ID of the Issue to modify.", required: true, loads: Objects::Issue, as: :issue
      argument :title, String, "The title for the issue.", required: false
      argument :body, String, "The body for the issue description.", required: false
      argument :body_version, String, "The hash of the issue body.  If supplied, the issue body will only be updated if the body_version matches the current body_version of the issue.", visibility: :internal, required: false
      argument :assignee_ids, [ID], "An array of Node IDs of users or bots for this issue.", required: false, loads: Interfaces::Actor
      argument :milestone_id, ID, "The Node ID of the milestone for this issue.", required: false, loads: Objects::Milestone
      argument :label_ids, [ID], "An array of Node IDs of labels for this issue.", required: false, loads: Objects::Label
      argument :labels, [Inputs::LabelUpdateInput], "An array of labels to set on this issue, each with optional rationale or suggest flag. Mutually exclusive with `labelIds`.", required: false, as: :labels_input, feature_flag: :update_issue_suggestions
      argument :state, Enums::IssueState, "The desired issue state.", required: false
      argument :project_ids, [ID], "An array of Node IDs for projects associated with this issue.", required: false
      argument :project_v2_ids, [ID], "An array of Node IDs for projects associated with this issue.", required: false, loads: Objects::ProjectV2, feature_flag: :memex_add_issue_to_project_in_gql_mutations
      argument :issue_type_id, ID, "The ID of the Issue Type for this issue.", required: false
      argument :issue_type, Inputs::IssueTypeUpdateInput, "The Issue Type to set on this issue, with optional rationale. Mutually exclusive with `issueTypeId`.", required: false, feature_flag: :update_issue_suggestions
      argument :agent_assignment, Inputs::AgentAssignmentInput, "Configuration for assigning an AI agent to this issue.", required: false

      read_arguments_from_replicas!

      error_fields
      field :issue, Objects::Issue, "The issue.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        issue = inputs[:issue]
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          # Use custom_role_update_issue which allows FGP roles
          access_control = :custom_role_update_issue

          permission.access_allowed?(access_control, resource: issue, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(execution_errors:, **inputs)
        read_from_selected_replicas([ApplicationRecord::Repositories, ApplicationRecord::Collab]) do
          issue = inputs[:issue]
          repository = issue.repository

          context[:permission].authorize_content(:issue, :update, issue: issue, repo: repository)

          # Block flagged accounts from creating suggestion or rationale records.
          # Mirrors the REST guard in `Api::Issues` for the suggestion path. The
          # suggestion records (Pending*Suggestion, UpdateIntent, EventAnnotation)
          # are not Spammable, and the triage agent's bot-attributed comment
          # bypasses the usual `user_hidden` gating, so without this guard a
          # flagged account or its agent could persist user-supplied text
          # outside the usual content-hidden filtering.
          if label_inputs_carry_suggest_or_rationale?(inputs[:labels_input]) ||
             type_input_carries_suggest_or_rationale?(inputs[:issue_type])
            ensure_actor_not_flagged_for_suggestions!(repository)
          end

          unless repository.has_issues?
            raise Errors::Forbidden, "Repository has issues disabled."
          end

          check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

          if context[:permission].integration_user_request?
            issue.performed_via_integration = context[:integration]
            issue.modifying_integration = context[:integration]
          end

          # This is a more general check that will include permissions check for apps & users alltogether
          # can_set_milestone and triageable_by are not implemented for apps
          can_viewer_write = repository.pushable_by?(context[:viewer]) || repository.resources.issues.writable_by?(context[:viewer])

          # If the viewer cannot at least triage the issue, they're limited by FGP
          is_fgp_limited = !context[:permission].access_allowed?(
            :triage_issue,
            resource: issue,
            repo: repository,
            current_org: repository.owner.is_a?(Organization) ? repository.owner : nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )

          # For FGP-limited users, validate they're only trying to update allowed fields
          if is_fgp_limited
            validate_fgp_limited_inputs!(inputs, issue)
          end

          # All props mentioned in the arguments which are not metadata props
          if inputs.key?(:title) || inputs.key?(:body)
            # issue's fields can be edited by people with write OR people with triage, if they are the authors
            unless can_viewer_write || context[:viewer] == issue.user
              message = "#{context[:viewer].display_login} does not have permission to update the issue #{issue.global_relay_id}."
              raise Errors::Forbidden.new(message)
            end
          end

          attributes = Issues::UpdateIssueAttributes.new
          attributes.title = update_attribute(inputs, :title)

          if inputs.key?(:milestone)
            if can_viewer_write || (!context[:actor].can_have_granular_permissions? && issue.can_set_milestone?(context[:viewer]))
              attributes.milestone = update_attribute(inputs, :milestone)
            else
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update the milestone on the issue #{issue.global_relay_id}.")
            end
          end

          # The viewer must have triage access to assign assignees and labels.
          can_viewer_set_metadata = can_viewer_write || issue.triageable_by?(context[:viewer])

          # `labels` and `label_ids` are mutually exclusive. `labels` is the newer
          # object form and may carry per-label `rationale` and `suggest` flags;
          # `label_ids` is kept for backwards compatibility.
          if inputs.key?(:labels_input) && inputs.key?(:labels)
            raise Errors::Unprocessable.new("`labels` and `labelIds` are mutually exclusive; provide only one.")
          end

          if (inputs.key?(:labels_input) && !inputs[:labels_input].nil?) ||
             (inputs.key?(:labels) && !inputs[:labels].nil?)
            unless can_viewer_set_metadata
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update metadata on the issue #{issue.global_relay_id}.")
            end
          end

          # Maps label_id => rationale text for labels being applied directly.
          # Suggested labels carry their rationale on the PendingLabelSuggestion.
          label_rationales = T.let({}, T::Hash[Integer, String])
          label_confidences = T.let({}, T::Hash[Integer, Issues::ConfidenceThreshold::Level])

          if inputs.key?(:labels_input) && !inputs[:labels_input].nil?
            label_inputs = inputs[:labels_input]

            assert_labels_in_repository!(label_inputs.map { |li| li[:label] }, issue)

            applied_labels, suggested_inputs, label_rationales, label_confidences =
              partition_label_suggestion_inputs(repository, label_inputs)

            persist_label_suggestions!(repository: repository, issue: issue, suggested_inputs: suggested_inputs)

            # Preserve "set" semantics for applied labels — suggested entries
            # do not influence the resulting label set on the issue.
            attributes.labels = Issues::UpdateIssueAttribute::Set.new(applied_labels)
          elsif inputs.key?(:labels) && !inputs[:labels].nil?
            labels = inputs[:labels]
            assert_labels_in_repository!(labels, issue)
            attributes.labels = Issues::UpdateIssueAttribute::Set.new(labels)
          end

          if inputs.key?(:assignees)
            unless can_viewer_set_metadata
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update metadata on the issue #{issue.global_relay_id}.")
            end

            assignees = inputs[:assignees]

            if assignees.present?
              assignees.each do |actor|
                if actor.is_a?(Organization) || actor.is_a?(Mannequin)
                  raise Errors::Forbidden.new("Only users and bots can be assigned.")
                end
              end

              bots = assignees.grep(Bot)
              if bots.any?
                GitHub::PrefillAssociations.prefill_associations(bots, :integration)
                validate_agent_bot_assignments!(bots, repository, actor: context[:viewer])
              end
            end

            attributes.assignees = update_attribute(inputs, :assignees)
          end

          if inputs.key?(:project_v2s) && FeatureFlag.vexi.enabled?(:memex_add_issue_to_project_in_gql_mutations, context[:viewer], default: false)
            projects = inputs[:project_v2s]
            permission_checks = projects.map do |project|
              project.async_viewer_can_write?(context[:viewer])
            end

            can_update_projects = Promise.all(permission_checks).then { |results| results.none?(false) }.sync
            unless can_update_projects
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to modify one or more projects on the issue #{issue.global_relay_id}.")
            end

            attributes.projects = update_attribute(inputs, :project_v2s)
          end

          # `issue_type` and `issue_type_id` are mutually exclusive. `issue_type` is the
          # newer object form and may carry a rationale string and `suggest` flag;
          # `issue_type_id` is kept for backwards compatibility.
          if inputs.key?(:issue_type) && inputs.key?(:issue_type_id)
            raise Errors::Unprocessable.new("`issueType` and `issueTypeId` are mutually exclusive; provide only one.")
          end

          issue_type_rationale = T.let(nil, T.nilable(String))
          issue_type_confidence = T.let(nil, T.nilable(Issues::ConfidenceThreshold::Level))
          issue_type_suggested = T.let(false, T::Boolean)
          if inputs.key?(:issue_type)
            issue_type_input = inputs[:issue_type]
            issue_type_rationale = issue_type_input[:rationale].presence
            issue_type_confidence = resolve_confidence_level(issue_type_input[:confidence])
            type_suggest = !!issue_type_input[:suggest]

            # The schema-level FF on `rationale`/`suggest` has already gated
            # visibility per viewer, but rollout is repo-scoped. When the FF
            # is off for this repo, silently strip both fields rather than
            # failing the whole `updateIssue` call (which may be carrying
            # unrelated changes like title/body/assignees).
            if (type_suggest || issue_type_rationale) && !update_issue_suggestions_enabled?(repository)
              type_suggest = false
              issue_type_rationale = nil
              issue_type_confidence = nil
            end

            # Confidence has its own flag, matching the REST API gate.
            unless update_issue_confidence_enabled?(repository)
              issue_type_confidence = nil
            end

            # `issue_type_input` is a Platform::Inputs::IssueTypeUpdateInput. When the
            # client passes the object but omits `issueTypeId`, treat it as a no-op for
            # the type itself (rationale alone has no target). When `issueTypeId` is
            # explicitly null, clear the type — matching the existing `issue_type_id`
            # scalar semantics.
            if issue_type_input.to_h.key?(:issue_type_id)
              type_id = issue_type_input[:issue_type_id]

              if type_id.nil?
                attributes.issue_type = Issues::UpdateIssueAttribute::Unset.new
              elsif type_suggest
                # Store as a pending suggestion instead of applying directly.
                resolved_type = Helpers::IssueTypes.load_by_id(type_id, context)
                if resolved_type
                  persist_type_suggestion!(
                    repository: repository,
                    issue: issue,
                    issue_type_id: T.must(resolved_type.id),
                    rationale: issue_type_rationale || "",
                    confidence: issue_type_confidence,
                  )
                  issue_type_suggested = true
                end
              else
                attributes.issue_type = Issues::UpdateIssueAttribute::Set.new(Helpers::IssueTypes.load_by_id(type_id, context))
              end
            end
          else
            attributes.issue_type = update_attribute(inputs, :issue_type_id).map { |id| Helpers::IssueTypes.load_by_id(id, context) }
          end

          attributes.state = update_attribute(inputs, :state).map { |s| Issues::State.deserialize(s) }

          if inputs.key?(:body)
            if inputs[:body_version] && inputs[:body_version] != issue.body_version
              raise Errors::StaleData.new(
                "The issue body for #{issue.global_relay_id} has been modified since you last fetched it."
              )
            end
            attributes.body = update_attribute(inputs, :body)
          end

          # Build copilot_context if an agent bot is being newly assigned
          copilot_context = nil
          if inputs.key?(:assignees) && inputs[:assignees].present?
            if FeatureFlag.vexi.enabled?(:sweagent_3p_assignment_graphql, context[:viewer], default: false)
              # Multi-agent: detect any newly-assigned agentic bot
              current_agent_bot_ids = agentic_bot_ids_from(inputs[:assignees])
              previous_agent_bot_ids = agentic_bot_ids_from(issue.assignees)
              new_agent_bot_ids = current_agent_bot_ids - previous_agent_bot_ids

              if new_agent_bot_ids.any?
                agent_assignment = inputs[:agent_assignment]
                target_repo = agent_assignment&.target_repository || repository

                if target_repo.present? && (!target_repo.writable_by?(context[:viewer]) || !target_repo.writable?)
                  execution_errors.add(Errors::Forbidden.new("Could not assign agent: target repository is not writable."))
                  # Remove new agent bots from assignees but continue with other updates
                  new_agent_ids_set = new_agent_bot_ids.to_set
                  attributes.assignees = Issues::UpdateIssueAttribute::Set.new(
                    inputs[:assignees].reject { |a| a.is_a?(Bot) && new_agent_ids_set.include?(a.id) }
                  )
                else
                  begin
                    # Don't set agent_id — the Orchestration layer handles per-agent routing
                    # via build_agent_specific_copilot_contexts
                    copilot_attributes = get_copilot_attributes(agent_assignment, repository, context[:ip], viewer: context[:viewer])

                    token = resolve_copilot_token(
                      viewer: context[:viewer],
                      entry_point: :update_issue_mutation,
                      user_session: context[:user_session],
                      request_token_value: context[:request_token]&.to_s,
                      repository: repository,
                    )

                    copilot_context = {
                      request_token: token.to_s,
                      attributes: copilot_attributes,
                    }
                  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
                    # Copilot SWE Agent integration is not available (e.g., on GHES)
                    # Skip agent assignment - copilot_context remains nil
                  end
                end
              end
            else
              # Legacy Copilot-only detection
              copilot_bot_assigned = inputs[:assignees].any? { |assignee| assignee.is_a?(Bot) && assignee.slug == Apps::Privileged::CopilotSWEAgent::SLUG }
              copilot_previously_assigned = issue.assignees.any? { |assignee| assignee.is_a?(Bot) && assignee.slug == Apps::Privileged::CopilotSWEAgent::SLUG }

              if copilot_bot_assigned && !copilot_previously_assigned
                agent_assignment = inputs[:agent_assignment]

                target_repo = agent_assignment&.target_repository || repository

                if target_repo.present? && (!target_repo.writable_by?(context[:viewer]) || !target_repo.writable?)
                  execution_errors.add(Errors::Forbidden.new("Could not assign Copilot: target repository is not writable."))
                  # Remove Copilot from assignees but continue with other updates
                  attributes.assignees = Issues::UpdateIssueAttribute::Set.new(
                    inputs[:assignees].reject { |a| a.is_a?(Bot) && a.slug == Apps::Privileged::CopilotSWEAgent::SLUG }
                  )
                else
                  begin
                    copilot_attributes = get_copilot_attributes(agent_assignment, repository, context[:ip], viewer: context[:viewer])

                    token = resolve_copilot_token(
                      viewer: context[:viewer],
                      entry_point: :update_issue_mutation,
                      user_session: context[:user_session],
                      request_token_value: context[:request_token]&.to_s,
                      repository: repository,
                    )

                    copilot_context = {
                      request_token: token.to_s,
                      attributes: copilot_attributes,
                    }
                  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
                    # Copilot SWE Agent integration is not available (e.g., on GHES)
                    # Skip agent assignment - copilot_context remains nil
                  end
                end
              end
            end
          end

          res = Issues.domain.update(
            issue,
            attributes,
            context[:viewer],
            copilot_context: copilot_context,
          )

          case res
          when GH::Result::Ok
            # Skip if the type was stored as a pending suggestion — its rationale
            # rides along with the PendingTypeSuggestion record itself.
            unless issue_type_suggested
              store_issue_type_rationale_annotation(
                issue: issue,
                repository: repository,
                actor: context[:viewer],
                rationale: issue_type_rationale,
                confidence: issue_type_confidence,
              )
            end

            store_label_rationale_annotations(
              issue: issue,
              repository: repository,
              actor: context[:viewer],
              label_rationales: label_rationales,
              label_confidences: label_confidences,
            )

            {
              issue: issue,
              actor: context[:viewer],
              errors: [],
            }
          when GH::Result::Error::ServiceUnavailable
            raise Errors::ServiceUnavailable
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)

            {
              issue: nil,
              errors: Platform::UserErrors.mutation_errors_for_model(issue, translate: { repository_id: "issueTypeId" }),
            }
          end
        end
      end

      def update_attribute(inputs, key)
        return Issues::UpdateIssueAttribute::Keep.new unless inputs.key?(key)
        if inputs[key].nil?
          Issues::UpdateIssueAttribute::Unset.new
        else
          Issues::UpdateIssueAttribute::Set.new(inputs[key])
        end
      end

      # Validates that all labels belong to the issue's repository, mirroring the
      # existing cross-repository check used for the legacy `label_ids` argument.
      def assert_labels_in_repository!(labels, issue)
        offender = labels.find { |label| label.repository_id != issue.repository_id }
        return unless offender

        GitHub.dogstats.increment "graphql.mutation.update_issue.cross_repository"
        raise Errors::NotFound.new("The label ('#{offender.global_relay_id}') and issue ('#{issue.global_relay_id}') don't belong to the same repository")
      end

      # `store_issue_type_rationale_annotation` lives in
      # `Platform::Helpers::IssueSuggestions`.

      # Validates that FGP-limited users are only trying to update fields they have FGP permissions for.
      # Raises Errors::Forbidden if they try to update fields they don't have permission for.
      def validate_fgp_limited_inputs!(inputs, issue)
        can_change_state = (issue.open? && issue.closable_by?(context[:viewer])) ||
                           (issue.closed? && issue.reopenable_by?(context[:viewer]))
        can_set_milestone = issue.can_set_milestone?(context[:viewer])

        inputs.each_key do |key|
          next if key == :issue # :issue is always present

          allowed = case key
          when :state
            can_change_state
          when :milestone
            can_set_milestone
          else
            false
          end

          unless allowed
            field_name = key.to_s.tr("_", " ")
            message = "#{context[:viewer].display_login} does not have permission to update the #{field_name} on the issue #{issue.global_relay_id}."
            raise Errors::Forbidden.new(message)
          end
        end
      end
    end
  end
end
