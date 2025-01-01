# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class ShowPayloadBuilder < BasePayloadBuilder
        include GitHub::TokenScanning::SecretScanningHelper
        include GitHub::TokenScanning::TokenScanningPostProcessingHelper
        include SecretScanning::Features::FeatureFlagHelper
        include UrlHelper

        TIMELINE_EVENTS_INITIAL_SHOW_COUNT = 3
        TIMELINE_EVENTS_LIMIT = 8
        BLOB_PADDING = 5

        sig { params(repo: Repository, user: User).void }
        def initialize(repo, user)
          super

          @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
        end

        sig { params(result: T.nilable(GitHub::TokenScanning::Service::Token), page: Integer).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def page_payload(result, page = 1)
          return if result.nil?

          validity_feature = SecretScanning::Features::Repo::ValidityChecks.new(@repo)
          alert = serialize_alert(result)

          owner_type = if @repo.owner&.user?
            "USER"
          elsif @repo.owner&.organization?
            "ORGANIZATION"
          else
            "UNKNOWN"
          end

          token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(@repo)
          delegated_closures_feature = SecretScanning::Features::Repo::DelegatedClosures.new(@repo)
          existing_closure_request = SecretScanning::Services::DelegatedAlertClosuresService.new.existing_alert_closure_request(@repo, result.number.to_s)
          existing_closure_request_number = existing_closure_request&.number || 0

          payload = {
            alert: alert.serialize,
            locations: result.included_locations.map { |location| serialize_location(location, result, @repo) },
            related_alerts: map_accessible_related_alerts(result.related_alerts),
            related_public_leaks: map_accessible_public_leaks(result.related_public_leaks),
            repository: {
              name: @repo.name,
              owner_display_login: @repo.owner_display_login,
              owner_type: owner_type,
              owner_belongs_to_business: @repo.owner&.business&.present?,
              visibility: @repo.visibility,
            },
            page: page,
            locations_per_page: SecretScanning::Services::AlertsService::LOCATIONS_PER_PAGE,
            total_locations_count: result.included_locations_count,
            has_ignored_locations: result.has_ignored_locations,
            ignored_locations_path: preferred_file_path(type: :token_scanning_configuration, repository: @repo),
            commit_author_mode: !@token_scanning.view_alerts_allowed?(@user),
            show_user_feedback_link: show_user_feedback_link?,
            user_feedback_notice: UserNotice::SECRET_SCANNING_FEEDBACK_NOTICE,
            host_name: GitHub.host_name_with_tenant,
            automatic_partner_validity_checks_enabled: validity_feature.enabled?,
            resolve_alerts_allowed: token_scanning_feature.resolve_alerts_allowed?(@user, result.commit_oids),
            wiki_incremental_scans_enabled: SecretScanning::Features::Repo::WikiScanning.new(@repo).enabled?,
            show_generic_secrets_feedback_notice: SecretScanning::Features::Repo::GenericSecrets.new(@repo).show_user_feedback_link?(@user) && alert.llm_detected,
            generic_secrets_feedback_notice: UserNotice::AI_DETECTED_SECRET_SCANNING_FEEDBACK_NOTICE,
            one_click_reporting_enabled: token_scanning_feature.one_click_reporting_enabled?(result),
            delegated_closures_enabled: delegated_closures_feature.enabled?,
            existing_closure_request_number: existing_closure_request_number,
            existing_closure_request_pending: existing_closure_request&.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending,
            show_closure_request_review_buttons: existing_closure_request && delegated_closures_feature.display_review_buttons_for_closure_request?(@user, existing_closure_request, alert),
            show_closure_request_cancel_button: existing_closure_request && delegated_closures_feature.display_cancel_button_for_closure_request?(@user, existing_closure_request, alert),
            user_can_review_closure_requests: delegated_closures_feature.user_can_review_closure_requests?(@user),
            current_user: AssignedUser.from_user(@user).serialize_ui,
            self_serve_banner: SecretScanning::Util::SelfServeBanner.banner_properties(@user, SecretScanning::Constants::SelfServeBannerSlugs::SECRET_PROTECTION_FEEDBACK_SURVEY),

            # Feature flags
            assignees_enabled: feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::SECRET_SCANNING_ALERT_ASSIGNEE),
          }

          if feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS) || feature_flag_enabled_in_hierarchy?(@user, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS)
            payload[:alert]["feature_flags"][FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS] = true
          end

          if feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS) || feature_flag_enabled_in_hierarchy?(@user, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS)
            payload[:alert]["feature_flags"][FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS] = true
          end

          if token_scanning_feature.ai_assisted_remediation_guidance_enabled?
            payload[:alert]["feature_flags"][FeatureFlags::AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS] = true
          end

          if token_scanning_feature.display_alert_permissions_on_show_page?
            payload[:alert]["feature_flags"][FeatureFlags::DISPLAY_ALERT_PERMISSIONS] = true
          end

          if feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::VALIDITY_CHECKS_ALLOWED_FOR_AWS_KEYS_WITHOUT_GROUPS)
            payload[:alert]["feature_flags"][FeatureFlags::VALIDITY_CHECKS_ALLOWED_FOR_AWS_KEYS_WITHOUT_GROUPS] = true
          end

          token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(result)

          if result.is_github_token?
            verification_status = alert.validity_last_checked.nil? ? "NOT_ATTEMPTED" : alert.validity
            if alert.raw_secret.present? && alert.created_at < 1.day.ago && verification_status == "NOT_ATTEMPTED"
              verification_status = "SCHEDULED_VALIDATION_MISSING"
            end
            tags = ["token_type:#{alert.token_type}", "token_id:#{result.id}", "verification_status:#{verification_status}", "metadata_available:#{token_metadata.present?}", "ghas_enabled:#{@repo.advanced_security_enabled?}"]
            GitHub.dogstats.increment("github/secret_scanning_experiences.token_validity", tags: tags)
          end

          if token_metadata.present?
            payload[:token_metadata] = {
                access_id: token_metadata.access_id,
                name: token_metadata.name,
                link: get_token_link(token_metadata),
                token_type: token_metadata.token_type,
                created_at: token_metadata.created_at,
                expires_at: token_metadata.expires_at,
                last_accessed_at: token_metadata.last_accessed_at,
                is_owner_suspended: token_metadata.is_owner_suspended,
              }

            if token_metadata.owner_id
              owner = User.find_by(id: token_metadata.owner_id)
              payload[:token_metadata][:owner] = serialize_displayed_user(owner)
            end
          end

          if result.is_custom?
            payload[:pattern_info] = {
              is_custom: true,
              render_link: can_access_custom_pattern?(result.custom_pattern),
              id: result.custom_pattern.custom_pattern_id,
              scope: result.custom_pattern.owner_scope
            }
          else
            payload[:pattern_info] = {
              is_custom: false,
              render_link: false,
              id: nil,
              scope: nil
            }
          end

          payload
        end

        sig { params(token_metadata: SecretScanning::Models::GitHubTokenMetadata).returns(T.nilable(String)) }
        def get_token_link(token_metadata)
          return nil if token_metadata.link.nil?

          token_owner = User.find_by(id: token_metadata.owner_id)

          if @user.id == token_owner&.id
            return token_metadata.link
          end

          if token_metadata.token_type == "GITHUB_TOKEN_V2"
            return nil unless token_metadata.link.include?("organizations")

            repo_owner = @repo.owner
            token_metadata.link if repo_owner.is_a?(::Organization) && SecurityProduct::Permissions::OrgAuthz.new(repo_owner, actor: @user).can_manage_org_security_products?
          end
        end

        sig { params(result: GitHub::TokenScanning::Service::Token, timeline: GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse).returns(T.untyped) }
        def timeline_payload(result, timeline)
          # The Twirp RPC to get timeline does not yet support pagination, so all events are in latest_ascending, see https://github.com/github/secret-scanning/issues/3719
          timeline_events = T.must(timeline.latest_ascending).events.to_a
          hide_events_in_between = show_load_all_timeline_ux?(timeline)
          latest_timeline_events = hide_events_in_between ? timeline_events.last(TIMELINE_EVENTS_INITIAL_SHOW_COUNT) : timeline_events
          earliest_timeline_events = hide_events_in_between ? timeline_events.first(TIMELINE_EVENTS_INITIAL_SHOW_COUNT) : []
          hidden_timeline_events = hide_events_in_between ? timeline_events.slice(TIMELINE_EVENTS_INITIAL_SHOW_COUNT..-(TIMELINE_EVENTS_INITIAL_SHOW_COUNT + 1)) : []

          {
            events_count: timeline.total_number_of_events,
            latest_events: to_react_timeline_events(latest_timeline_events),
            earliest_events: to_react_timeline_events(earliest_timeline_events),
            hidden_events: to_react_timeline_events(T.must(hidden_timeline_events)),
          }
        end

        sig { params(result: T.nilable(GitHub::TokenScanning::Service::Token)).returns(T.nilable(T::Array[T.untyped])) }
        def locations_payload(result)
          return [] if result.nil?

          result.included_locations.map { |location| serialize_location(location, result, @repo) }
        end

        sig { params(custom_pattern: T.untyped).returns(T::Boolean) }
        def can_access_custom_pattern?(custom_pattern)
          return false unless custom_pattern
          return false if custom_pattern.state == :DELETED

          case custom_pattern.owner_scope
          when :REPOSITORY_SCOPE
            return true if SecurityProduct::Permissions::RepoAuthz.new(@repo, actor: @user).can_manage_repo_security_products?
          when :ORGANIZATION_SCOPE
            repo_owner = @repo.owner
            return true if repo_owner.is_a?(::Organization) && SecurityProduct::Permissions::OrgAuthz.new(repo_owner, actor: @user).can_manage_org_security_products?
          else
            return false
          end

          false
        end

        # Technically reason can be either a symbol or an integer.
        # If it's an integer, the value is unknown, so we return nil.
        sig { params(reason: T.any(Symbol, Integer)).returns(T.nilable(String)) }
        def self.from_sym_exemption_reason(reason)
          case reason
          when :EXEMPTION_REASON_FALSE_POSITIVE
            "false_positive"
          when :EXEMPTION_REASON_REVOKED
            "revoked"
          when :EXEMPTION_REASON_USED_IN_TESTS
            "used_in_tests"
          when :EXEMPTION_REASON_WONT_FIX
            "wont_fix"
          else
            nil
          end
        end

        sig { params(status: T.any(Symbol, Integer)).returns(T.nilable(String)) }
        def self.from_sym_exemption_status(status)
          case status
          when :PENDING
            "pending"
          when :APPROVED
            "approved"
          when :REJECTED
            "rejected"
          when :CANCELLED
            "cancelled"
          else
            nil
          end
        end

        private

        sig { params(events: T::Array[GitHub::Proto::SecretScanning::Api::V2::TimelineEvent]).returns(T.nilable(T::Array[{ type: T.any(Symbol, Integer), time: T.untyped }])) }
        def to_react_timeline_events(events)
          return [] unless events.present?

          alert_assignee_ff_enabled = feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::SECRET_SCANNING_ALERT_ASSIGNEE)

          # Collect all user IDs that need to be queried, so we don't have to query within a loop
          user_ids = []
          events.each do |event|
            user_ids << event.actor if event.actor.present?
            assignment_change_event = event.assignment_change
            if alert_assignee_ff_enabled && assignment_change_event.present?
              user_ids << assignment_change_event.assigned_user_id if assignment_change_event.assigned_user_id.present?
              user_ids << assignment_change_event.unassigned_user_id if assignment_change_event.unassigned_user_id.present?
            end
          end
          user_ids.uniq!
          users_by_id = User.where(id: user_ids).index_by(&:id)



          events.map do |event|
            timeline_event = {
              type: event.type,
              time: Time.at(T.must(event.time).seconds, T.must(event.time).nanos, :nsec),
            }

            if event.actor.present?
              actor_user = users_by_id[event.actor]

              if actor_user.present?
                timeline_event[:actor] = get_user_metadata(actor_user)
              end
            end

            if event.resolution.present?
              timeline_event[:resolution] = {
                type: T.must(event.resolution).type.to_s.downcase,
                comment: T.must(event.resolution).comment,
              }
            end

            if event.validity.present?
              timeline_event[:validity] = {
                validity: T.must(event.validity).validity
              }
            end

            if event.exemption_request.present?
              timeline_event[:exemption_request] = {
                  requester_comment: event.exemption_request&.requester_comment,
                  reason: event.exemption_request&.reason ? self.class.from_sym_exemption_reason(T.must(event.exemption_request&.reason)) : nil,
                  status: event.exemption_request&.status ? self.class.from_sym_exemption_status(T.must(event.exemption_request&.status)) : nil,
              }
            elsif event.exemption_response.present?
              timeline_event[:exemption_response] = {
                  reviewer_comment: event.exemption_response&.reviewer_comment
              }
            end

            assignment_change_event = event.assignment_change
            if alert_assignee_ff_enabled && assignment_change_event.present?
              assigned_user = assignment_change_event.assigned_user_id.present? ? users_by_id[assignment_change_event.assigned_user_id] : nil
              unassigned_user = assignment_change_event.unassigned_user_id.present? ? users_by_id[assignment_change_event.unassigned_user_id] : nil

              timeline_event[:assignment_change] = {
                assigned_user: get_user_metadata(assigned_user),
                unassigned_user: get_user_metadata(unassigned_user)
              }
            end

            timeline_event
          end
        end

        sig { params(user: T.nilable(User)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def get_user_metadata(user)
          return nil unless user.present?
          serialize_displayed_user(user)
        end

        # Returns true if we should hide some timeline events and show a `Load all` button
        sig { params(timeline: T.untyped).returns(T::Boolean) }
        def show_load_all_timeline_ux?(timeline)
          timeline.total_number_of_events > TIMELINE_EVENTS_LIMIT
        end

        sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_git_location(location)
          return {} if location.nil?

          {
            path: location.path,
            start_line: location.start_line,
            end_line: location.end_line,
            start_column: location.start_column,
            end_column: location.end_column,
            found_in_archive: location.found_in_archive?,
            commit: {
              oid: location.commit_oid,
            },
          }
        end

        sig { params(commit: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_commit(commit)
          return {} if commit.nil?

          {
            message: commit.short_message_text,
            author: {
              avatar_url: commit.author&.primary_avatar_url,
            },
            created_at: commit.created_at,
          }
        end

        sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Boolean) }
        def blob_available?(location)
          return false if location.found_in_archive?
          return false if location.blob.nil?

          true
        end

        sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Array[String]) }
        def code_snippet_lines(location)
          return [] if location.blob.nil?
          blob = T.must(location.blob)

          # skip loading lines if truncated since we will skip later regardless
          return [] if blob.truncated?

          begin
            colorized_lines = blob.colorized_lines || []
          rescue => e # rubocop:todo Lint/RescueException
            # gracefully fail and report errors if getting code lines fails for any reason,
            # as it is not critical to the experience and may fail for reasons outside of our control
            Failbot.report(e, blob_oid: location.blob_oid, repository_id: @repo.id, user_id: @user.id)
            GitHub.logger.error("failed to get colorized lines for secret scanning show page", { exception: e, "gh.secret_scanning.blob_oid": location.blob_oid })
            return []
          end

          blob_slice_end = location.end_line + BLOB_PADDING - 1
          blob_slice_start = location.start_line - BLOB_PADDING - 1
          if blob_slice_start < 0
            blob_slice_start = 0
          end
          if blob_slice_end > colorized_lines.length
            blob_slice_end = colorized_lines.length
          end

          colorized_lines[blob_slice_start..blob_slice_end]
        end

        sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_blob(location)
          return {} if location.blob.nil?

          blob = location.blob
          {
            oid: location.blob_oid,
            lines: code_snippet_lines(location),
            is_truncated: blob&.truncated?,
            is_text: blob&.text?,
            language: blob&.language ? blob.language.name.parameterize : "text",
          }
        end

        sig { params(location: T.untyped, issue: T.nilable(Issue)).returns(String) }
        def build_issue_heading_text(location, issue)
          title = !issue.nil? ? "#{issue.title}" : "Issue"
          "#{title} ##{location.content_number}"
        end

        sig { params(location: T.untyped, discussion: T.nilable(Discussion)).returns(String) }
        def build_discussion_heading_text(location, discussion)
          title = !discussion.nil? ? "#{discussion.title}" : "Discussion"
          "#{title} ##{location.content_number}"
        end

        sig { params(location: T.untyped, pull_request: T.nilable(Issue)).returns(String) }
        def build_pull_request_heading_text(location, pull_request)
          title = !pull_request.nil? ? "#{pull_request.title}" : "Pull Request"
          "#{title} ##{location.content_number}"
        end

        sig { returns(T::Boolean) }
        def show_user_feedback_link?
          SecretScanning::Features::Repo::TokenScanning.new(@repo).feedback_link_enabled? &&
            !@user.dismissed_notice?(UserNotice::SECRET_SCANNING_FEEDBACK_NOTICE)
        end

        sig { params(location: GitHub::TokenScanning::Service::TokenLocation, result: T.untyped, repository: Repository).returns(T::Hash[T.untyped, T.untyped]) }
        def serialize_location(location, result, repository)
          serialized_location = {
            content_type: location.content_type
          }

          case location.content_type
          when :REPOSITORY_BLOB
            serialized_location.merge!(serialize_git_location(location))
            serialized_location.merge!({
              enable_commit_and_blob_links: true,
            })

            commit = repository.find_commit(location.commit_oid)
            serialized_location[:commit].merge!(serialize_commit(commit)) if commit.present?

            return serialized_location unless blob_available?(location)

            serialized_location[:blob] = serialize_blob(location)
            serialized_location[:blob].merge!({
              link_accessible: true,
            })
          when :WIKI_BLOB
            serialized_location.merge!(serialize_git_location(location))
            serialized_location.merge!({
              enable_commit_and_blob_links: repository.has_wiki?,
            })

            wiki = repository.unsullied_wiki
            return serialized_location unless wiki.exist?

            commit = repository.find_wiki_commit(location.commit_oid)
            serialized_location[:commit].merge!(serialize_commit(commit)) if commit.present?

            return serialized_location unless blob_available?(location)

            serialized_location[:blob] = serialize_blob(location)

            path_with_no_ext = location.path.chomp(File.extname(location.path))
            serialized_location[:blob].merge!({
              link_accessible: !wiki.pages.find(path_with_no_ext).nil?,
            })
          when :ISSUE_TITLE, :ISSUE_BODY
            issue = repository.issues.find_by(number: location.content_number)
            if issue.nil?
              serialized_location.merge!({
                heading_text: build_issue_heading_text(location, issue),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            issue_author = issue.user

            serialized_location.merge!({
              heading_text: build_issue_heading_text(location, issue),
              content_number: issue.number,
              created_at: issue.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(issue_author),
              is_deleted: false,
              is_user_hidden: false,
            })

            if issue.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: issue.editor.display_login
                }
              )
            end
          when :ISSUE_COMMENT
            issue = repository.issues.find_by(number: location.content_number)
            if issue.nil?
              serialized_location.merge!({
                heading_text: build_issue_heading_text(location, issue),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment = IssueComments::Public.by_id(location.content_id, repository_id: repository.id)
            if comment.nil?
              serialized_location.merge!({
                heading_text: build_issue_heading_text(location, issue),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment_author = comment.user

            serialized_location.merge!({
              heading_text: build_issue_heading_text(location, issue),
              content_number: issue.number,
              created_at: comment.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(comment_author),
              is_deleted: false,
              is_user_hidden: comment.user_hidden?,
            })

            if comment.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: comment.editor.display_login
                }
              )
            end
          when :DISCUSSION_TITLE, :DISCUSSION_BODY
            discussion = repository.discussions.find_by(number: location.content_number)
            if discussion.nil?
              serialized_location.merge!({
                heading_text: build_discussion_heading_text(location, discussion),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            discussion_author = discussion.user

            serialized_location.merge!({
              heading_text: build_discussion_heading_text(location, discussion),
              content_number: discussion.number,
              created_at: discussion.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(discussion_author),
              is_deleted: false,
              is_user_hidden: false,
            })

            if discussion.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: discussion.editor.display_login
                }
              )
            end
          when :DISCUSSION_COMMENT
            discussion = repository.discussions.find_by(number: location.content_number)
            if discussion.nil?
              serialized_location.merge!({
                heading_text: build_discussion_heading_text(location, discussion),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment = repository.discussion_comments.find_by(id: location.content_id)
            if comment.nil?
              serialized_location.merge!({
                heading_text: build_discussion_heading_text(location, discussion),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment_author = comment.user

            serialized_location.merge!({
              heading_text: build_discussion_heading_text(location, discussion),
              content_number: discussion.number,
              created_at: comment.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(comment_author),
              is_deleted: false,
              is_user_hidden: comment.user_hidden?,
            })

            if comment.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: comment.editor.display_login
                }
              )
            end
          when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY
            pr = repository.issues.find_by(number: location.content_number)
            if pr.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            pr_author = pr.user

            serialized_location.merge!({
              heading_text: build_pull_request_heading_text(location, pr),
              content_number: pr.number,
              created_at: pr.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(pr_author),
              is_deleted: false,
              is_user_hidden: false,
            })

            if pr.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: pr.editor.display_login
                }
              )
            end
          when :PULL_REQUEST_COMMENT
            pr = repository.issues.find_by(number: location.content_number)
            if pr.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment = IssueComments::Public.by_id(location.content_id, repository_id: repository.id)
            if comment.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment_author = comment.user

            serialized_location.merge!({
              heading_text: build_pull_request_heading_text(location, pr),
              content_number: pr.number,
              created_at: comment.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(comment_author),
              is_deleted: false,
              is_user_hidden: comment.user_hidden?,
            })

            if comment.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: comment.editor.display_login
                }
              )
            end
          when :PULL_REQUEST_REVIEW, :PULL_REQUEST_TIMELINE_COMMENT
            pr = repository.issues.find_by(number: location.content_number)
            if pr.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            review = T.must(pr.pull_request).reviews.find_by(id: location.content_id)
            if review.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            review_author = review.user

            serialized_location.merge!({
              heading_text: build_pull_request_heading_text(location, pr),
              content_number: pr.number,
              created_at: review.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(review_author),
              is_deleted: false,
              is_user_hidden: review.user_hidden?,
            })

            if review.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: review.editor.display_login
                }
              )
            end
          when :PULL_REQUEST_REVIEW_COMMENT
            pr = repository.issues.find_by(number: location.content_number)
            if pr.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment = repository.pull_request_review_comments.find_by(id: location.content_id)
            if comment.nil?
              serialized_location.merge!({
                heading_text: build_pull_request_heading_text(location, pr),
                is_deleted: true,
                is_user_hidden: false,
              })
              return serialized_location
            end

            comment_author = comment.user

            serialized_location.merge!({
              heading_text: build_pull_request_heading_text(location, pr),
              content_number: pr.number,
              created_at: comment.created_at,
              content_id: location.content_id,
              author: serialize_displayed_user(comment_author),
              is_deleted: false,
              is_user_hidden: comment.user_hidden?,
            })

            if comment.editor.present?
              serialized_location.merge!(
                editor: {
                  display_login: comment.editor.display_login
                }
              )
            end
          end
          serialized_location
        end

        sig { params(related_alerts: T::Array[GitHub::TokenScanning::Service::RelatedToken]).returns(SecretScanning::Models::RelatedAlerts) }
        def map_accessible_related_alerts(related_alerts)
          return SecretScanning::Models::RelatedAlerts.new(alerts: [], more_exist: false) if related_alerts.empty?

          repos = Repository.where(id: related_alerts.map(&:repository_id).uniq).to_a

          accessible_repo_ids = SecretScanning::AccessControl::FineGrainedPermissions
            .async_batch_check_fgp(@user, :view_secret_scanning_alerts, repos)
            .with_permission

          out = []
          related_alerts.each do |related_alert|
            break if out.size >= 5
            next unless accessible_repo_ids.include?(related_alert.repository_id)

            this_repo = repos.find { |repo| repo.id == related_alert.repository_id }
            next if this_repo.nil?

            out << serialize_related_alert(related_alert, this_repo)
          end

          SecretScanning::Models::RelatedAlerts.new(
            alerts: out,
            more_exist: related_alerts.size > out.size
          )
        end

        sig { params(related_alert: GitHub::TokenScanning::Service::RelatedToken, repository: Repository).returns(SecretScanning::Models::RelatedAlerts::RelatedAlert) }
        def serialize_related_alert(related_alert, repository)
          SecretScanning::Models::RelatedAlerts::RelatedAlert.new(
            repository_id: related_alert.repository_id,
            repository_owner: repository.owner_display_login,
            repository_name: repository.name,
            repository_visibility: repository.visibility,
            repository_icon: repository.repo_type_icon,
            number: related_alert.number,
            token_type: related_alert.token_type
          )
        end

        sig { params(related_public_leaks: T::Array[GitHub::TokenScanning::Service::RelatedPublicLeak]).returns(SecretScanning::Models::RelatedPublicLeaks) }
        def map_accessible_public_leaks(related_public_leaks)
          return SecretScanning::Models::RelatedPublicLeaks.new(leaks: [], more_exist: false) if related_public_leaks.empty?

          repos = Repository.where(id: related_public_leaks.map(&:repository_id).uniq).to_a

          readable_repos = repos.select do |repo|
            repo.readable_by?(@user)
          end.to_set { |repo| repo.id }

          out = []
          related_public_leaks.each do |related_public_leak|
            break if out.size >= 5
            next unless readable_repos.include?(related_public_leak.repository_id)

            this_repo = repos.find { |repo| repo.id == related_public_leak.repository_id }
            next if this_repo.nil?

            out << serialize_related_public_leak(related_public_leak, this_repo)
          end

          SecretScanning::Models::RelatedPublicLeaks.new(
            leaks: out,
            more_exist: related_public_leaks.size > out.size
          )
        end

        sig { params(related_public_leak: GitHub::TokenScanning::Service::RelatedPublicLeak, repository: Repository).returns(SecretScanning::Models::RelatedPublicLeaks::RelatedPublicLeak) }
        def serialize_related_public_leak(related_public_leak, repository)
          location = GitHub::TokenScanning::Service::TokenLocation.new(related_public_leak.location, repository)
          SecretScanning::Models::RelatedPublicLeaks::RelatedPublicLeak.new(
            repository_id: related_public_leak.repository_id,
            repository_owner: repository.owner_display_login,
            repository_name: repository.name,
            location: serialize_location(location, nil, repository)
          )
        end
      end
    end
  end
end
