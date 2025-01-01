# typed: true
# frozen_string_literal: true

module Voltron
  class DiscussionsFragmentsController < DiscussionsController
    include FragmentController
    include GitHub::RateLimitedRequest

    rate_limit_requests max: 5000, ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, key: :rate_limit_key_by_ip

    before_action :require_voltron_header, unless: -> { Rails.env.development? || GitHub.dynamic_lab? }
    before_action :handle_transferred_discussion, only: :discussion_layout
    before_action :handle_deleted_discussion, only: :discussion_layout
    before_action :handle_issue_redirect, only: :discussion_layout
    before_action :redirect_if_org_discussion, only: :discussion_layout

    isolate_before_actions :authorization_required,
      :ensure_advisory_workspace_allowed,
      :network_privilege_check,
      :perform_conditional_access_checks,
      to: :discussion_layout

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Iam,
      ApplicationRecord::Spokes,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Ballast,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      only: [:content_1]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Ballast,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      ApplicationRecord::Iam,
      only: [:content_2]

    depends_on_clusters  ApplicationRecord::Spokes, optional: true,
      only: [:content_2]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Spokes,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Iam,
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Memex,
      only: [:discussion_layout]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Ballast,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      ApplicationRecord::Iam,
      only: [:sidebar_content]


    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Spokes, optional: true,
      only: [:sidebar_content]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:discussion_layout, :content_1, :content_2, :sidebar_content], optional: true

    def discussion_layout # rubocop:todo GitHub/UseRestfulActions
      discussion = self.discussion
      return render_404 if discussion.nil?

      if discussion.converting? || discussion.error?
        return render("discussions/show_conversion", locals: { discussion: discussion })
      end

      set_hovercard_subject(discussion)

      render "discussions/show",
        locals: {
          discussion: discussion,
          timeline: discussion_timeline,
          current_repository: current_repository,
          use_sticky_header: true,
        }
    end

    def content_1 # rubocop:todo GitHub/UseRestfulActions
      return render_404 if discussion.nil?

      mark_discussion_timeline_as_read
      async_mark_thread_as_read discussion

      DiscussionTimeline::PermissionPreloader.load_for(
        discussion_timeline,
        can_interact_with_repo: can_interact_with_repo?,
        show_stats_name: :voltron_preload_permissions,
      )

      discussion_timeline.preload_comments(show_stats_name: :voltron_preload_comments)
      discussion_timeline.preload_body_html(show_stats_name: :voltron_preload_body_html)

      render(
        Discussions::ContentComponent.new(
          timeline: discussion_timeline,
          parsed_discussions_query: parsed_discussions_query,
          org_param: org_param,
        ), layout: fragment_layout
      )
    end

    def content_2 # rubocop:todo GitHub/UseRestfulActions
      return render_404 if discussion.nil?

      mark_discussion_timeline_as_read

      DiscussionTimeline::PermissionPreloader.load_for(
        discussion_timeline,
        can_interact_with_repo: can_interact_with_repo?,
        show_stats_name: :voltron_preload_permissions,
      )

      discussion_timeline.preload_comments(show_stats_name: :voltron_preload_comments)
      discussion_timeline.preload_body_html(show_stats_name: :voltron_preload_body_html)

      render Discussions::CollapsibleTimelineComponent.new(timeline: discussion_timeline, org_param: org_param), layout: fragment_layout
    end

    def sidebar_content # rubocop:todo GitHub/UseRestfulActions
      discussion = self.discussion
      return render_404 if discussion.nil?

      DiscussionTimeline::PermissionPreloader.load_for(
        discussion_timeline,
        can_interact_with_repo: can_interact_with_repo?,
        show_stats_name: :voltron_preload_permissions,
      )

      discussion_timeline.preload_labels(show_stats_name: :voltron_preload_labels)

      limited_participants =
        discussion.participants_for(current_user, limit: ONE_POINT_FIVE_TIMES_MAX_AVATARS)

      render(
        Discussions::SidebarContainerComponent.new(
          discussion: discussion,
          timeline: discussion_timeline,
          participants: limited_participants,
          current_repository: current_repository,
          events: discussion_timeline.events,
          deferred_content: user_feature_enabled?(:notifications_async_discussions_subscription_button),
          org_param: org_param,
        ), layout: fragment_layout
      )
    end

    private

    def discussion_timeline_render_context
      case action_name
      when "content_1", "content_2"
        DiscussionTimeline::VoltronTimelineRenderContext.new(
          discussion,
          viewer: current_user,
          sort: timeline_sort,
          cap_filter: cap_filter,
          first_half: action_name == "content_1",
        )
      when "discussion_layout"
        DiscussionTimeline::VoltronBodyRenderContext.new(
          discussion,
          viewer: current_user,
          cap_filter: cap_filter
        )
      when "sidebar_content"
        DiscussionTimeline::SidebarRenderContext.new(
          discussion,
          viewer: current_user,
          cap_filter: cap_filter
        )
      end
    end

    # Overrides Discussions::BaseController
    def handle_renamed_discussion_org(exception)
      new_org = exception.org.display_login
      GitHub.dogstats.increment("renamed_org_discussion_redirects", tags: ["path:voltron"])

      render_404 and return unless match = request.fullpath.scan(%r{\A.*/show/orgs/([\w.-]+)/(\d+)/}).first

      old_org_name, discussion_number, _suffix = match

      GitHub.logger.info(
        "Renamed org discussion redirect in voltron",
        "code.namespace" => self.class.name,
        "code.function" => action_name,
        "gh.org.old_login" => old_org_name,
        "gh.org.login" => exception.org.login, # rubocop:disable GitHub/DoNotAllowLogin login is ok in logs
        "gh.controller.new_path" => new_path,
      )

      redirect_to org_discussion_path(new_org, discussion_number)
    end

    def require_voltron_header
      if request.headers["HTTP_X_GITHUB_USE_VOLTRON_DISCUSSIONS_SHOW"] != "1"
        render_404
      end
    end

    def redirect_if_org_discussion
      current_repository = self.current_repository
      return unless current_repository

      discussion = self.discussion
      if current_repository.organization_discussion.present? && !is_org_level? && discussion
        redirect_to org_discussion_path(current_repository.owner, discussion.number)
      end
    end
  end
end
