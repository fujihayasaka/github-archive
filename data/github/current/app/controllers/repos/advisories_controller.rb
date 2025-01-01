# typed: true
# frozen_string_literal: true

class Repos::AdvisoriesController < Repos::AdvisoryBaseController
  include AdvisoryDB::CvssScore
  include CommentsHelper
  include GitHub::RateLimitedRequest

  # Require login for drafting an advisory or privately reporting a vulnerability.
  before_action :require_login, only: [:new, :create]
  before_action :non_spammy_user_required, only: [:new, :create, :update, :update_body, :request_cve]
  before_action :can_create_draft_or_pvd?, only: [:new, :create, :open_workspace]
  before_action :authorize_advisory_management, except: [:index, :show, :new, :create, :open_workspace, :update, :update_body, :show_partial, :edit_history_log, :add_credit, :accept_credit, :decline_credit, :decline_credit_and_block_user, :remove_collaborator]
  before_action :authorize_advisory_writable, only: [:open_workspace, :update, :update_body, :show_partial, :edit_history_log, :remove_collaborator]
  before_action :authorize_advisory_credits, only: [:add_credit, :accept_credit, :decline_credit, :decline_credit_and_block_user]
  before_action :advisory, except: [:add_credit, :index, :new, :create]

  after_action :set_repo_advisory_request_stats_tags, except: [:add_credit, :index, :new]

  javascript_bundle :advisories
  stylesheet_bundle :advisories

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesPushes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:index]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Notify,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:merge_box]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:autocomplete_collaborator]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    only: [:edit_history_log]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    only: [:show_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:workspace]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new, :edit_history_log, :show_partial, :workspace],
    optional: true

  # Rate limit creating new repo advisories for both owners and PVD contributors.
  rate_limit_requests(
    only: :create,
    max: 10,
    key: :new_repo_advisory_rate_limit_key,
    ttl: 1.hour,
    at_limit: :instrument_new_repo_advisory_rate_limit_at_limit,
    if: :should_rate_limit?,
  )

  def index
    view = create_view_model(
      RepositoryAdvisories::IndexView,
      current_repository: current_repository,
      state: params[:state],
      page: params[:page] || 1,
    )
    render "repos/advisories/index", locals: { view: view }
  end

  def new
    repository_advisory = current_repository.repository_advisories.new
    repository_advisory.affected_products.build

    view = create_view_model(
      RepositoryAdvisories::ShowView,
      repository: current_repository,
      advisory: repository_advisory,
    )

    render "repos/advisories/new", locals: { view: view }
  end

  def create
    # Repository advisories and advisory credits share the same database
    # connection, but abilities use a separate connection so we'll use a nested
    # transaction.
    notice_message = T.let(nil, T.nilable(String))
    _error_message = T.let(nil, T.nilable(String))
    RepositoryAdvisory.transaction do
      Ability.transaction do
        advisory.save!

        # Skip adding credits if this is an innersource advisory enabled repo.
        next unless advisory_credits_enabled?

        # Add the current user as a collaborator on the advisory if it is a
        # private vulnerability report and then give them credit.
        if advisory.external?
          advisory.add_and_credit_pvr_author(current_user)

          notice_message = "Thank you for reporting a vulnerability to #{current_repository.owner_display_login}/#{current_repository.name}. Maintainers have been notified and will review your submission."
        elsif credits_attributes.present?
          # Allow crediting at the time of creation of a repository advisory.
          # Saving credits has to be performed after the repository advisory is created
          # otherwise the credits will fail validation due to no foreign key.
          advisory.update!(credits_attributes: credits_attributes)
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      _error_message = e.message
    end

    if advisory.persisted?
      GlobalInstrumenter.instrument("repository_advisory.create", {
        repository_advisory: advisory,
      })

      redirect_to gh_repository_advisory_path(advisory), notice: notice_message
    else
      flash.now[:error] = "Advisory could not be created."

      view = create_view_model(
        RepositoryAdvisories::ShowView,
        repository: current_repository,
        advisory: advisory,
      )

      render "repos/advisories/new", status: :unprocessable_entity, locals: { view: view }
    end
  end

  def preload_advisory_records(view, advisory) # rubocop:todo GitHub/UseRestfulActions
    records_to_preload = view.timeline_items.grep(RepositoryAdvisoryComment)
    records_to_preload << advisory if view.body_present?
    view.preload_comment_with_avatar_data(records_to_preload)
  end

  def show
    # If you try, for example, to edit an existing repository advisory that for
    # unknown reasons does not have at least one associated affected product,
    # the form will not show any affected product entries. As such, we need to
    # build a blank one here so the form can present something to the user.
    if advisory.affected_products.empty?
      advisory.affected_products.build
    end

    view = create_view_model(
      RepositoryAdvisories::ShowView,
      repository: current_repository,
      advisory: advisory,
      cap_filter: cap_filter
    )

    if view.readable?
      preload_advisory_records(view, advisory)
      async_mark_thread_as_read advisory
      mark_credit_notification_as_read advisory
      render "repos/advisories/show_wrapper", locals: { view: view }
    else
      render_404
    end
  end

  def update
    update_successful = false

    if !credit_types_valid?
      advisory.errors.add(:base, "Invalid credits changes.")
      advisory.assign_attributes(update_advisory_params.except(:credits_attributes))
    elsif stale_model?(advisory)
      advisory.errors.add(:base, "The content you are editing has changed. Please copy your edits and refresh the page.")
      # Set the desired attributes but do not save them to the DB
      # This will allow us to show the user their edits so that they can
      # copy before refreshing
      advisory.assign_attributes(update_advisory_params)
    else
      update_successful = advisory.handle_update(current_user, update_advisory_params)

      if update_successful
        GlobalInstrumenter.instrument("repository_advisory.update", {
          repository_advisory: advisory,
          actor: current_user,
          request_curation: advisory.published?,
        })

        advisory.notify_socket_subscribers
      end
    end

    respond_to do |format|
      format.html do
        if update_successful
          redirect_to gh_repository_advisory_path(advisory), notice: "The advisory was updated."
        else
          flash.now[:error] = "Unable to update advisory: #{advisory.errors.full_messages.join(", ")}"
          show
        end
      end

      format.json do
        if update_successful
          render json: advisory_payload(advisory)
        else
          render json: { errors: advisory.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def update_body # rubocop:todo GitHub/UseRestfulActions
    # We no longer support the RepositoryAdvisory#body attribute, so we now
    # prevent this endpoint from being hit if the body attribute is nil.

    if advisory.body.blank?
      raise ActionController::UnpermittedParameters.new([:body])
    end

    text =
      if operation = TaskListOperation.from(params[:task_list_operation])
        operation.call(advisory.body)
      else
        params[:repository_advisory][:body]
      end

    advisory.update_body(text, current_user) if text

    respond_to do |wants|
      wants.html do
        redirect_to :back
      end
      wants.json do
        if advisory.valid?
          render json: {
            source: advisory.body,
            body: advisory.body_html,
            newBodyVersion: advisory.body_version,
            editUrl: show_comment_edit_history_path(advisory.global_relay_id),
          }
        else
          render json: { errors: advisory.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def delete_workspace # rubocop:todo GitHub/UseRestfulActions
    repository_to_delete = advisory.workspace_repository
    repository_to_delete.remove(current_user)
    redirect_to gh_repository_advisory_path(advisory), notice: "The temporary fork was deleted!"
  end

  def publish # rubocop:todo GitHub/UseRestfulActions
    if advisory.workspace_clean? && publish_advisory(current_user)
      redirect_to gh_repository_advisory_path(advisory), notice: "The advisory was published!"
    else
      redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, something went wrong. Please try again." }
    end
  end

  def request_cve # rubocop:todo GitHub/UseRestfulActions
    view = T.let(
      create_view_model(RepositoryAdvisories::ShowView, repository: current_repository, advisory: advisory),
      RepositoryAdvisories::ShowView
    )

    return render_404 if view.innersource_advisories_enabled?

    if view.viewer_can_request_cve?
      RepositoryAdvisory::CVE.request_cve(advisory, current_user)

      redirect_to gh_repository_advisory_path(advisory), notice: "A CVE has been requested for this advisory."
    else
      redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, you can’t request a CVE for this advisory at this time." }
    end
  end

  # assumption is that only users authorized to edit will end up pinging
  # this end point for live updates.
  def show_partial # rubocop:todo GitHub/UseRestfulActions
    partial_view_model = create_view_model(
      RepositoryAdvisories::ShowView,
      repository: current_repository,
      advisory: advisory,
      cap_filter: cap_filter
    )

    case params[:partial]
    when "repository_advisory/timeline"
      # if we're rendering comments, we have to
      # preload the query before calling `preloaded_platform_object`
      # in the view template.
      partial_view_model.preload_comment_with_avatar_data(advisory.comments.to_a)
      render partial: "repos/advisories/timeline", formats: :html, locals: { view: partial_view_model }
    when "repository_advisory/body"
      partial_view_model.preload_comment_with_avatar_data([advisory])
      render partial: "repos/advisories/body", formats: :html, locals: { view: partial_view_model }
    when "repository_advisory/title"
      render partial: "repos/advisories/title", formats: :html, locals: { view: partial_view_model }
    when "repository_advisory/collaborators_and_publishers"
      render partial: "repos/advisories/sidebar/collaborators_and_publishers", formats: :html, locals: { view: partial_view_model }
    else
      render_404
    end
  end

  def open_workspace # rubocop:todo GitHub/UseRestfulActions
    if advisory.closed?
      redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, can't add a repository to a security advisory once it is closed." }
    elsif advisory.workspace_repository
      redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, a repository already exists for this security advisory." }
    elsif !advisory.workspace_openable_by?(current_user)
      redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, only maintainers and reporters can add a repository to a security advisory." }
    elsif current_repository.archived?
      redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, creating forks for archived repositories is not allowed." }
    else
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, current_user)

      if workspace_repo.persisted?
        GlobalInstrumenter.instrument("repository_advisory.workspace_open", {
          repository_advisory: advisory,
          actor: current_user,
        })

        redirect_to gh_repository_advisory_path(advisory), notice: "Hang tight. We're creating the repository for you."
      else
        redirect_to gh_repository_advisory_path(advisory), flash: { error: "Sorry, something went wrong. Please try again." }
      end
    end
  end

  def workspace # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless workspace = advisory.workspace_repository

    if workspace.creating?
      head :accepted
    else
      render partial: "repos/advisories/repo_body", locals: {
        view: create_view_model(RepositoryAdvisories::ShowView,
          user: current_user,
          repository: current_repository,
          advisory: advisory
        )
      }
    end
  end

  def merge_box # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      RepositoryAdvisories::MergeBoxView,
      advisory: advisory,
    )

    # explicitly force firing off the merge commit job if needed
    advisory.enqueue_mergeable_updates

    respond_to do |format|
      format.html do
        if view.merge_state == :unknown
          head :accepted
        else
          render partial: "repos/advisories/merge_box", locals: { view: view }
        end
      end
    end
  end

  def merge # rubocop:todo GitHub/UseRestfulActions
    if stale_merge_submitted?(advisory, params["head_shas"])
      redirect_to gh_repository_advisory_path(advisory),
        flash: { error: "At least one pull request was updated. Please try again." }
      return
    end

    batch_merge = advisory.build_batch_merge(actor: current_user)
    success, results = batch_merge.perform if batch_merge.valid?

    if success
      redirect_to gh_repository_advisory_path(advisory),
        notice: "The temporary private fork’s pull requests have been merged."
    elsif results
      details = results.map { |pull, error| "##{pull.number} - #{error.fail_message}" }.to_sentence
      redirect_to gh_repository_advisory_path(advisory),
        flash: { error: "There were problems merging these pull requests: #{details}" }
    else
      redirect_to gh_repository_advisory_path(advisory),
        flash: { error: "These pull requests cannot be merged. See below for details." }
    end
  end

  def autocomplete_collaborator # rubocop:todo GitHub/UseRestfulActions
    autocomplete_params = { query: params[:q], current_repository: current_repository, organization: current_organization }

    respond_to do |format|
      format.html_fragment do
        render partial: "repos/advisories/sidebar/autocomplete",
          formats: :html,
          locals: { view: create_view_model(RepositoryAdvisories::AutocompleteView, autocomplete_params) }
      end
    end
  end

  def add_collaborator # rubocop:todo GitHub/UseRestfulActions
    potential_collaborator = find_collaborator
    return render_404 unless potential_collaborator

    if can_collaborate?(potential_collaborator)
      advisory.add_collaborator(potential_collaborator, actor: current_user)
    end

    advisory.notify_socket_subscribers

    if request.xhr?
      head :ok
    else
      redirect_to repository_advisory_path(id: advisory)
    end
  end

  def remove_collaborator # rubocop:todo GitHub/UseRestfulActions
    removed_collab = find_collaborator
    return render_404 unless removed_collab

    # We can only check this after we know who is being removed
    return render_404 unless can_manage_advisories? || removed_collab == current_user

    advisory.remove_collaborator(removed_collab, actor: current_user)
    advisory.notify_socket_subscribers

    if request.xhr?
      render html: ""
    else
      if removed_collab == current_user
        notice = "You have been removed as a collaborator."
        if advisory.readable_by?(removed_collab)
          notice += " You may now view this #{advisory.label} as read only."
        end
      else
        notice = "You have removed #{removed_collab} as a collaborator."
        if advisory.readable_by?(removed_collab)
          notice += " They may now view this #{advisory.label} as read only and will be notified when the advisory is published."
        end
      end

      if advisory.readable_by?(current_user)
        redirect_to repository_advisory_path(id: advisory), notice: notice
      else
        redirect_to repository_advisories_path(advisory.repository.owner), notice: notice
      end
    end
  end

  def edit_history_log # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "repos/advisories/description_edit_history_log", locals: { comment: advisory }
      end
    end
  end

  def add_credit # rubocop:todo GitHub/UseRestfulActions
    credit_login = params[:credit_login]
    if credit_login.blank?
      return head :unprocessable_entity
    end
    recipient = User.find_by!(login: credit_login)
    advisory_credit = AdvisoryCredit.new(recipient: recipient)

    render partial: "repos/advisories/credits/form_row",
      locals: {
        index: params.require(:credit_index),
        view: create_view_model(RepositoryAdvisories::CreditView,
          advisory_credit: advisory_credit,
          viewer_can_manage: true,
          is_unsaved_advisory_credit: true,
        )
      }
  end

  def accept_credit # rubocop:todo GitHub/UseRestfulActions
    credit_to_accept = advisory.credits.find_by!(recipient_id: current_user.id)
    credit_to_accept.accept(actor: current_user)

    redirect_to gh_repository_advisory_path(advisory), notice: "You successfully accepted credit."
  end

  def decline_credit # rubocop:todo GitHub/UseRestfulActions
    credit_to_decline = advisory.credits.find_by!(recipient_id: current_user.id)
    credit_to_decline.decline(actor: current_user)

    redirect_to gh_repository_advisory_path(advisory), notice: "You declined credit."
  end

  def decline_credit_and_block_user # rubocop:todo GitHub/UseRestfulActions
    credit_to_decline = advisory.credits.find_by!(recipient_id: current_user.id)
    credit_to_decline.decline(actor: current_user)

    user_to_block = credit_to_decline.creator

    if user_to_block
      current_user.block(user_to_block)
      redirect_to gh_repository_advisory_path(advisory), notice: "You declined credit and blocked #{user_to_block}."
    else
      redirect_to gh_repository_advisory_path(advisory), notice: "You declined credit."
    end
  end

  def accept_pvd # rubocop:todo GitHub/UseRestfulActions
    if advisory.external?
      begin
        # Only update the accepted status if the advisory is not yet accepted.
        advisory.set_accepted(actor: current_user)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
        flash.now[:error] = "There was a problem accepting the PVD."
        show
        return
      end

      redirect_to gh_repository_advisory_path(advisory), notice: "Vulnerability report accepted as draft advisory."
    else
      render_404
    end
  end

  private

  memoize def advisory
    if params[:action] == "create"
      current_repository.repository_advisories.build(create_advisory_params)
    else
      super
    end
  end

  # override AbstractRepositoryController#allowed_from_referrer_sanitization
  #
  # by default, we always set the Referrer-Policy header but this is
  # overridden for public repos via #allowed_from_referrer_sanitization
  #
  # if we are in the show action, skip the referrer-override unless
  # we're showing a published advisory; if we're showing a published
  # advisory, allow the allowed_from_referrer_sanitization to proceed.
  def allowed_from_referrer_sanitization
    if action_name == "show"
      super if advisory.published?
    else
      super
    end
  end

  def find_collaborator
    return nil unless user_collaborator_param

    if current_organization
      if team_name = team_collaborator_param
        current_organization.teams.where(slug: team_name).first
      else
        User.find_by_login(user_collaborator_param)
      end
    else
      User.find_by_login(user_collaborator_param)
    end
  end

  # If adding a user, that user just needs read access to the repository.
  # If adding a team, the team must belong to the current organization.
  def can_collaborate?(collab)
    advisory.actor_can_collaborate?(collab)
  end

  memoize def current_organization
    if current_repository.owner.organization?
      current_repository.owner
    end
  end

  def advisory_payload(advisory)
    {
      title: advisory.title,
      page_title: helpers.repository_advisory_page_title(advisory),
    }
  end

  # Before action to render a 404 if the user can't manage an advisory.
  def authorize_advisory_management
    render_404 unless can_manage_advisories?
  end

  def can_manage_advisories?
    current_repository.advisory_management_authorized_for?(current_user)
  end

  # Before action to render a 404 if a user can't manage an advisory and also can't create a PVD.
  def can_create_draft_or_pvd?
    render_404 unless can_manage_advisories? || pvd_authorized?
  end

  def pvd_authorized?
    helpers.use_pvd_workflow?
  end

  def authorize_advisory_credits
    render_404 unless advisory_credits_enabled?
  end

  def advisory_credits_enabled?
    !GitHub.single_or_multi_tenant_enterprise? && !innersource_advisories_enabled?
  end

  memoize def innersource_advisories_enabled?
    SecurityProduct::InnersourceAdvisories.new(current_repository).enabled?
  end

  def require_login
    redirect_to_login(new_repository_advisory_url(current_repository.owner, current_repository)) unless logged_in?
  end

  def should_rate_limit?
    logged_in? && !can_manage_advisories?
  end

  def advisory_params
    params.require(:repository_advisory).permit(
      :title,
      :severity,
      :cve_id,
      :cve_selection,
      :description,
      :cvss_v3,
      :cvss_v4,
      credits_attributes: [
        :_destroy,
        :id,
        :recipient_id,
        :credit_type
      ],
      cwes: [],
      affected_products_attributes: [
        :_destroy,
        :id,
        :affected_versions,
        :ecosystem,
        :ecosystem_other,
        :package,
        :patches,
        :affected_functions
      ]
    )
  end

  def credits_attributes
    update_advisory_params[:credits_attributes]
  end

  # These are the parameters used when updating a repository advisory.
  #
  # We also iterate over the form parameters for each advisory credit and set
  # the creator_id if the credit is being created. We do this in the controller
  # rather than in the form to prevent spoofing.
  memoize def update_advisory_params
    update_advisory_params = advisory_params

    # Do not save credits information if this repo has innersource advisories enabled.
    update_advisory_params.delete(:credits_attributes) unless advisory_credits_enabled?

    if update_advisory_params[:credits_attributes].present?
      update_advisory_params[:credits_attributes].each_value do |credit_attributes|
        if credit_attributes[:id].blank?
          credit_attributes[:creator_id] = current_user.id
        end
      end
    end

    if update_advisory_params.key?(:cwes)
      update_advisory_params[:cwes] = CWE.where(id: update_advisory_params[:cwes])
    else
      update_advisory_params[:cwes] = []
    end

    if update_advisory_params.key?(:cvss_v3)
      if update_advisory_params[:severity] == "cvss" || update_advisory_params[:severity] == "cvss_v3"
        # User chose to use CVSS v3
        if update_advisory_params[:cvss_v3].present?
          update_advisory_params[:severity] = severity_from_cvss(update_advisory_params[:cvss_v3])
        else
          update_advisory_params[:severity] = nil
          update_advisory_params[:cvss_v3] = nil
        end
      else
        # User chose an explicit severity
        update_advisory_params[:cvss_v3] = nil
      end
    end

    if update_advisory_params.key?(:cvss_v4)
      if update_advisory_params[:severity] == "cvss_v4"
        # User chose to use CVSS v4
        if update_advisory_params[:cvss_v4].present?
          update_advisory_params[:severity] = severity_from_cvss(update_advisory_params[:cvss_v4])
        else
          update_advisory_params[:severity] = nil
          update_advisory_params[:cvss_v4] = nil
        end
      else
        # User chose an explicit severity
        update_advisory_params[:cvss_v4] = nil
      end
    end

    cve_selection = update_advisory_params.delete(:cve_selection)
    # user chose requesting CVE so clear any existing CVE ID
    if cve_selection == "requesting"
      update_advisory_params[:cve_id] = nil
    end

    update_advisory_params[:affected_products_attributes]&.each_value do |affected_product|
      ecosystem_other = affected_product.delete(:ecosystem_other)
      if affected_product[:ecosystem] == "other"
        affected_product[:ecosystem] = ecosystem_other
      end
    end

    # `accepted` and `external` cannot be changed through editing the advisory for security reasons.
    # `external` cannot be changed at all, and `accepted` requires admin permissions to change and must be updated
    # through the `#accept_pvd` endpoint.
    update_advisory_params.delete :accepted
    update_advisory_params.delete :external

    update_advisory_params
  end

  # These are the parameters used when creating a repository advisory.
  #
  # In addition to the form parameters and advisory credit creator_id values,
  # we set the author_id of the repository advisory itself. We do this in the
  # controller rather than in the form to prevent spoofing.
  memoize def create_advisory_params
    result = update_advisory_params.merge(author_id: current_user.id).except(:credits_attributes)

    # Repo advisory is external/PVD if the user cannot manage advisories.
    result[:external] = !can_manage_advisories?
    # Repo advisory is automatically accepted if it's not external as it's authored by a maintainer.
    result[:accepted] = can_manage_advisories?

    result
  end

  def user_collaborator_param
    params[:member]
  end

  def team_collaborator_param
    user_collaborator_param.split("/", 2)[1]
  end

  def stale_merge_submitted?(advisory, submitted_head_shas)
    expected_shas = advisory.open_pull_requests.map(&:head_sha)

    expected_shas.sort != submitted_head_shas.sort
  end

  def publish_advisory(publisher)
    if advisory.set_published(actor: publisher)
      GlobalInstrumenter.instrument("repository_advisory.publish", {
        repository_advisory: advisory,
        actor: publisher,
      })

      true
    else
      false
    end
  end

  def mark_credit_notification_as_read(advisory)
    credit_for_viewer = logged_in? && advisory.credits.find_by(recipient_id: current_user.id)
    return unless credit_for_viewer

    async_mark_thread_as_read credit_for_viewer
  end

  def new_repo_advisory_rate_limit_key
    "new_repo_advisory_rate_limiter:#{current_user.id}:#{current_repository.id}"
  end

  def instrument_new_repo_advisory_rate_limit_at_limit
    GitHub.dogstats.increment("new_repo_advisory.improvement_rate_limited")
  end

  # Add context tags to the default request stats. They will be sent to datadog # as `{service_name}/{key}:{value}`.
  def set_repo_advisory_request_stats_tags
    return unless advisory && advisory.persisted?

    request.env[GitHub::TaggingHelper::REPO_ADVISORY_SOURCE_TYPE_KEY] = advisory.external? ? "external" : "internal"
  end

  def non_spammy_user_required
    return unless GitHub.spamminess_check_enabled?
    return unless current_user.spammy?
    return render_404 unless logged_in?
    return if current_user.employee?

    render_404
  end

  # Are credit type attributes valid?
  # We have to do this because ActiveRecord::Enum does not perform validation checks
  # and will throw an ArgumentError instead of an ActiveModel::ValidationError.
  def credit_types_valid?
    credits_attributes&.each do |_, attributes|
      # Set a default value of `analyst` so that if the attributes do not include credit_type this still works.
      unless AdvisoryCredit.credit_types.include?(attributes.fetch(:credit_type, "analyst"))
        return false
      end
    end

    true
  end
end
