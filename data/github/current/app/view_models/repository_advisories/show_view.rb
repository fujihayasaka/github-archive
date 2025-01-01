# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::Memoizer
    include Repos::AdvisoriesHelper

    attr_reader :repository, :advisory, :form_advisory

    delegate :ghsa_id,
             :author,
             :publisher,
             :created_at,
             :publishable?,
             :form_filled_out?,
             :published?,
             :published_at,
             :closed?,
             :closed_at,
             :recently_touched_branches,
             :pull_requests,
             :workspace_repository,
             :cve_id,
             :cve_url,
             :workspace_clean?,
             :cve_request_pending?,
             :user_is_pvd_submitter?,
             :report_count,
             :top_report_reason,
             :last_reported_at,
             :viewer_can_report,
             :viewer_relationship,
             :stafftools_url,
             :description_matches_template?,
             to: :advisory

    def initialize(args)
      super
      @advisory_comments_by_id = {}
      @advisory_context = RepositoryAdvisory::Adapter::Context.new(advisory, repository, current_user, args[:cap_filter])
      @advisory_loader = RepositoryAdvisory::Loader::AdvisoryComments.new(@advisory_context)
      @has_unread_notifications = args[:has_unread_notifications] || false
    end

    def preload_comment_with_avatar_data(comments)
      return if comments.empty?
      # preload all the data required for advisory comments
      @advisory_loader.preload(comments)

      comments.each do |comment|
        @advisory_comments_by_id[comment] = RepositoryAdvisory::Adapter::CommentAdapter.new(@advisory_context, comment)
      end
    end

    def get_preloaded_adapter(ar_object)
      item_node = @advisory_comments_by_id[ar_object]

      unless item_node
        raise Platform::Errors::Internal, "expected an item from the Adapter data that we preloaded"
      end

      item_node
    end

    memoize def admin?
      advisory.adminable_by?(current_user)
    end

    memoize def collaborator?
      advisory.writable_by?(current_user)
    end

    memoize def manager?
      repository.advisory_management_authorized_for?(current_user)
    end

    memoize def readable?
      advisory.readable_by?(current_user)
    end

    def draft?
      advisory.open?
    end

    def affected_products
      advisory.affected_products.group_by do |affected_product|
        [affected_product.ecosystem, affected_product.package]
      end.sort_by do |(_ecosystem, package), _affected_products|
        package
      end.map do |(ecosystem, package), affected_products|
        {
          ecosystem: ecosystem,
          package: package,
          affected_versions: affected_products.map(&:affected_versions),
          patched_versions: affected_products.map(&:patches),
        }
      end
    end

    def missing_affected_versions?
      advisory.affected_products.size == 0 || advisory.affected_products.any? { |affected_product| affected_product.affected_versions.blank? }
    end

    def missing_description?
      advisory.description.blank?
    end

    def missing_severity?
      advisory.severity.blank?
    end

    def missing_patches?
      advisory.affected_products.size == 0 || advisory.affected_products.any? { |affected_product| affected_product.patches.blank? }
    end

    def repository_archived?
      repository.archived?
    end

    def repository_empty?
      repository.empty?
    end

    memoize def description
      context = { current_user: current_user, entity: repository }
      context[:organization] = organization if organization

      advisory_description = advisory.get_description(current_user)

      html_content = GitHub::Goomba::MarkdownPipeline.to_html(advisory_description, context, cache_settings: { use_cache: true })
      html_content = GitHub::Goomba::NoReferrerPipeline.to_html(html_content) unless published?
      html_content.html_safe  # rubocop:disable Rails/OutputSafety
    rescue EncodingError, TypeError => e
      Failbot.report(e, "gh.repo.id": repository.id, "gh.vulnerability.id": advisory.id, "gh.ghsa_id": advisory.ghsa_id)
      nil
    end

    memoize def title
      advisory.get_title(current_user)
    end

    # We used to treat the RepositoryAdvisory#body attribute like a comment,
    # and so sometimes we have to check for it, eg see repos/advisories/_body
    def body_present?
      !advisory.body.nil?
    end

    memoize def body
      context = { current_user: current_user, entity: repository }
      context[:organization] = organization if organization
      html_content = GitHub::Goomba::MarkdownPipeline.to_html(advisory.body, context, nil)
      html_content = GitHub::Goomba::NoReferrerPipeline.to_html(html_content) unless published?
      html_content.html_safe  # rubocop:disable Rails/OutputSafety
    rescue EncodingError, TypeError => e
      Failbot.report(e, "gh.repo.id": repository.id, "gh.vulnerability.id": advisory.id, "gh.ghsa_id": advisory.ghsa_id)
      nil
    end

    memoize def severity
      advisory.severity
    end

    def being_reviewed?
      show_external_state? && !manager?
    end

    def externally_submitted?
      advisory.external?
    end

    def accepted?
      advisory.accepted?
    end

    # Whether an unpublished advisory was submitted as a PVD advisory but hasn't been accepted yet
    sig { returns(T::Boolean) }
    def show_external_state?
      pvd_authorized_repo? && externally_submitted? && !accepted? && draft?
    end

    def state
      advisory.state == "open" ? "draft" : advisory.state
    end

    def state_label
      if show_external_state?
        "Triage"
      else
        state.humanize
      end
    end

    def state_icon
      case state
      when "published" then "check"
      when "closed" then "x"
      else "git-pull-request"
      end
    end

    def state_badge_icon
      case state
      when "draft" then "issue-draft"
      when "closed" then "shield-check"
      when "published" then "shield"
      else "shield"
      end
    end

    def state_text_color
      case state
      when "draft" then :muted
      when "closed" then :danger
      when "published" then :done
      end
    end

    def state_color
      case state
      when "draft" then "default"
      when "closed" then "merged"
      when "published" then "open"
      end
    end

    def workspace
      advisory.workspace_repository
    end

    def workspace_creating?
      workspace.creating?
    end

    def workspace_path
      urls.advisory_workspace_path(repository.owner, repository, advisory)
    end

    def default_url
      workspace.http_url
    end

    def viewer_authored?
      current_user ? current_user.id == advisory.author_id : false
    end

    def viewer_published?
      current_user ? current_user.id == advisory.publisher_id : false
    end

    memoize def pending_credit_for_viewer
      return nil unless current_user

      advisory.credits.pending.find_by(recipient_id: current_user.id)
    end

    memoize def timeline_items
      advisory.timeline_for(current_user).select do |item|
        # Let's make doubly sure that the current user can view these timeline
        # items before sending them to the view.
        item.readable_by?(current_user)
      end
    end

    memoize def admin_users
      repository.members(action: :admin)
    end

    memoize def unique_collaborating_users
      advisory.collaborating_users - admin_users - [advisory.owner]
    end

    memoize def admin_teams
      return [] unless organization

      organization.visible_teams_for(current_user).where(id: Ability.where(
        actor_type: "Team",
        subject_id: repository.id,
        subject_type: "Repository",
        priority: Ability.priorities[:direct],
        action: Ability.actions[:admin],
      ).pluck(:actor_id))
    end

    memoize def unique_collaborating_teams
      advisories = advisory.collaborating_teams_visible_to_user(current_user) - admin_teams
    end

    def organization
      return advisory.owner if advisory.owner.organization?

      nil
    end

    def show_credit_action_button?(timeline_item)
      return false unless current_user
      return false unless timeline_item == latest_credit_event_for_viewer

      viewer_credit = advisory.credits.find_by(recipient_id: current_user.id)
      return false unless viewer_credit

      (timeline_item.credit_accepted? && viewer_credit.accepted?) ||
        (timeline_item.credit_declined? && viewer_credit.declined?)
    end

    # Differs from use_pvd_workflow? in that it only checks if the repository is authorized for PVD,
    # whereas use_pvd_workflow? also tells us if the user is authorized to use PVD.
    sig { returns(T::Boolean) }
    memoize def pvd_authorized_repo?
      AdvisoryDB::Pvd.authorized_repo?(repo: repository)
    end

    sig { returns(T::Boolean) }
    memoize def innersource_advisories_enabled?
      repository.innersource_advisories_enabled?
    end

    sig { returns(T::Boolean) }
    def show_cve_form?
      cve_enabled? &&
      !use_pvd_workflow?(repository:)
    end

    sig { returns(T::Boolean) }
    def show_cve_sidebar?
      cve_enabled?
    end

    def show_workspace_box?
      draft? && collaborator?
    end

    def show_accept_pvd_box?
      show_external_state? && manager?
    end

    def show_merge_box?
      draft? && collaborator? && workspace.present?
    end

    def show_publish_box?
      collaborator? && (draft? || cve_requestable?)
    end

    sig { returns(T::Boolean) }
    def cve_requestable?
      cve_enabled? && RepositoryAdvisory::CVE.cve_requestable?(advisory)
    end

    def cve_filled?
      cve_id.present?
    end

    # Viewer permissions
    #
    # The methods below use viewer_may_* and viwer_can_* naming.
    #
    # A viewer_may_* method signifies that the current user is *allowed* to
    # perform an action, regardless of whether that action is currently
    # possible.
    #
    # A viewer_can_* method typically combines the current_user's permission
    # (viewer_may_*) with a check of the data state.
    #
    # For example, it's possible that the current user *may* publish the
    # advisory, but the user *cannot* actually publish the advisory because we
    # haven't collected all of the required information yet. The fact that the
    # user *may* publish allows us to show the publish button. The fact that
    # they *cannot* means that button will be disabled.

    def viewer_can_manage_collaborators?
      admin?
    end

    def viewer_can_remove_collaborator?(collaborator)
      collaborator? && collaborator == current_user
    end

    def viewer_can_create_workspace?
      workspace.blank? && viewer_may_create_workspace?
    end

    def viewer_may_create_workspace?
      admin? || authorized_pvd_author_collaborator?
    end

    def viewer_can_publish?
      publishable? && viewer_may_publish?
    end

    def viewer_may_publish?
      admin?
    end

    def viewer_can_delete_workspace?
      admin? && (GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(current_user) || GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(repository))
    end

    # Whether the user can request a CVE and the advisory is eligible to be assigned one.
    def viewer_can_request_cve?
      cve_requestable? && viewer_may_request_cve?
    end

    # Whether the current user is allowed to request a CVE for this advisory.
    def viewer_may_request_cve?
      cve_enabled? && admin?
    end

    def show_comment_and_close_box?
      viewer_can_comment? || viewer_can_close? || viewer_can_reopen?
    end

    def viewer_can_comment?
      !published? && viewer_may_comment?
    end

    def viewer_may_comment?
      collaborator?
    end

    def viewer_can_close?
      draft? && viewer_may_close?
    end

    def viewer_may_close?
      admin? || authorized_pvd_author_collaborator?
    end

    def authorized_pvd_author_collaborator?
      pvd_authorized_repo? && user_is_pvd_submitter?(current_user) && collaborator?
    end

    def viewer_can_reopen?
      closed? && viewer_may_reopen?
    end

    def viewer_may_reopen?
      admin?
    end

    def show_github_review_info?
      !closed? && collaborator? && !innersource_advisories_enabled?
    end

    # For now, we will not allow innersource advisories to be published since
    # we are still figuring out how we will store them in the database.
    def disable_publish_button?
      !viewer_can_publish? || innersource_advisories_enabled?
    end

    def viewer_can_edit_title?
      viewer_may_edit_title?
    end

    def viewer_may_edit_title?
      collaborator?
    end

    def unpublished_and_viewer_read_only?
      !published? && !collaborator? && readable?
    end

    def show_state_badge?
      collaborator? || user_is_pvd_submitter?(current_user)
    end

    def show_severity_badge?
      severity.present?
    end

    def show_abuse_reports?
      return false unless current_user&.site_admin?
      return false if report_count.nil?
      report_count > 0
    end

    def show_stafftools_link?
      current_user&.site_admin?
    end

    def show_comment_count?
      collaborator? || comment_count > 0
    end

    memoize def comment_count
      comment_count = timeline_items.count do |item|
        item.is_a?(RepositoryAdvisoryComment)
      end

      # Remove whenever we migrate away RepositoryAdvisory#body comments.
      comment_count += 1 if body_present?

      comment_count
    end

    def viewer_may_manage_credits?
      credits_enabled? && collaborator?
    end

    sig { returns(T::Boolean) }
    memoize def show_credits?
      credits_enabled? && credits.any?
    end

    memoize def credits
      return CreditView.for_advisory_credits([], current_user: current_user, viewer_can_manage: viewer_may_manage_credits?) if innersource_advisories_enabled?

      advisory_credits = advisory.credits.preload(:recipient)
      advisory_credits = advisory_credits.accepted unless viewer_may_manage_credits?

      CreditView.for_advisory_credits(advisory_credits, current_user: current_user, viewer_can_manage: viewer_may_manage_credits?)
    end

    memoize def form_credits
      CreditView.for_advisory_credits(
        form_advisory.credits,
        current_user: current_user,
        viewer_can_manage: viewer_may_manage_credits?
      )
    end

    def link_to_global_advisory?
      advisory.vulnerability&.globally_available?
    end

    def publish_url
      urls.publish_repository_advisory_path(repository.owner, repository, advisory)
    end

    def request_cve_url
      urls.request_cve_repository_advisory_path(repository.owner, repository, advisory)
    end

    def show_edit_form_on_load?
      form_advisory.errors.any?
    end

    def after_initialize
      helpers.extend(PackageDependenciesHelper)

      @form_advisory = @advisory

      # The page to see an advisory has its details as well as a form to edit
      # those values. When you submit an invalid edit (e.g. with an invalid
      # field), the view has to discern between the original valid data (that
      # appears in the details) and the modified invalid data (that appears in
      # the edit form, using @form_advisory).
      if @advisory.persisted? && @advisory.errors.any?
        @advisory = RepositoryAdvisory.find(@advisory.id)
      end
    end

    def show_advisory_credits_feature_popover?
      credits_enabled? &&
        logged_in? &&
        collaborator? &&
        !current_user.dismissed_notice?("feature_repository_advisory_credits")
    end

    def cve_selection_options
      [
        ["Request CVE ID later", "requesting"],
        ["I have an existing CVE ID", "existing"],
      ]
    end

    def cve_selection_option
      form_advisory.cve_id.present? ? "existing" : "requesting"
    end

    def title_is_user_populated?
      (form_advisory.persisted? || form_advisory.errors.any?).presence
    end

    # We make the "Request CVE" button and messaging primary in all cases
    # except the following:
    #
    # - The viewer can publish the advisory but _cannot_ request a CVE
    # - The viewer can publish the advisory and a CVE request is already pending
    # - The viewer can publish the advisory and a CVE request has already been added
    #
    # In the above cases, we feature the "Publish advisory" button instead.
    def emphasize_publication?
      return true if cve_filled?
      return false unless viewer_can_publish?
      !viewer_can_request_cve? || cve_request_pending?
    end

    # We use the default (rather than primary) button styling if both the
    # "Publish advisory" and "Request CVE" buttons are disabled.
    def viewer_cannot_publish_nor_request_cve?
      !viewer_can_publish? && !viewer_can_request_cve?
    end

    def has_unread_notifications?
      @has_unread_notifications
    end

    private

    def credit_event_for_viewer?(timeline_item)
      timeline_item.is_a?(RepositoryAdvisoryEvent) &&
        timeline_item.credit_event? &&
        current_user&.id == timeline_item.actor_id
    end

    memoize def latest_credit_event_for_viewer
      return nil unless current_user

      timeline_items.reverse_each.detect do |timeline_item|
        credit_event_for_viewer?(timeline_item)
      end
    end

    sig { returns(T::Boolean) }
    def cve_enabled?
      T.let(!GitHub.single_or_multi_tenant_enterprise?, T::Boolean) &&
        !innersource_advisories_enabled?
    end

    sig { returns(T::Boolean) }
    def credits_enabled?
      T.let(!GitHub.single_or_multi_tenant_enterprise?, T::Boolean) &&
        !innersource_advisories_enabled?
    end
  end
end
