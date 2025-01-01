# typed: false
# frozen_string_literal: true

module ProjectCardControllerActions
  include PlatformHelper

  ARCHIVED_CARDS_PAGE_SIZE = 25

  def render_422(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def render_project_cards_index(project:)
    GitHub.dogstats.distribution_time("projects.paginated_cards.dist.list") do
      column = project.columns.find_by_id!(params[:column_id])
      paginated_cards = column.paginated_ordered_cards_for(current_user, after: params[:after])
      respond_to do |format|
        format.html do
          render partial: "project_columns/cards", locals: {
            cards: paginated_cards[:cards],
            next_after: paginated_cards[:next_after],
            project: project,
            column: column,
          }
        end
      end
    end
  end

  def render_archived_project_cards(project:)
    scope = project.cards.archived

    scope = if params[:card_id]
      scope.where(id: params[:card_id])
    else
      scope.reorder(archived_at: :desc).limit(ARCHIVED_CARDS_PAGE_SIZE)
    end

    archived_cards = ProjectCardRedactor.new(current_user, scope).cards
    column_select_tag_options = project.columns.map { |col| [col.name, col.id] }

    respond_to do |format|
      format.html do
        render partial: "projects/archived_cards", locals: {
          project: project,
          cards: archived_cards,
          next_page: next_archived_cards_page_for(scope, current_page: 1),
          card_id: params[:card_id],
          query: nil,
          column_id: "all",
          column_select_tag_options: [["All columns", "all"]] + column_select_tag_options,
        }
      end
    end
  end

  def render_search_archived_project_cards(project:)
    filters_present = false

    if params[:column_id] == "all"
      scope = project.cards
    else
      filters_present = true
      scope = project.columns.find_by_id!(params[:column_id]).cards
    end

    scope = scope.archived.reorder(archived_at: :desc).limit(ARCHIVED_CARDS_PAGE_SIZE)
    current_page = params.fetch(:page, 1).to_i

    if current_page > 1
      scope = scope.offset((current_page - 1) * ARCHIVED_CARDS_PAGE_SIZE)
    end

    if params[:query].present?
      filters_present = true

      # We do two queries here: one for issue cards and one for note cards.
      # This is a temporary hack because of a bug that excludes note cards
      # in private repo projects from results. In the future, we should fix
      # this bug and cut this down to one query that doesn't specify card type.
      card_id_queries = [
        Search::Queries::ProjectCardQuery.new(
          phrase: params[:query],
          project_id: project.id,
          card_type: "issue",
          current_user: current_user,
        ),
        Search::Queries::ProjectCardQuery.new(
          phrase: params[:query],
          project_id: project.id,
          card_type: "note",
          current_user: current_user,
        ),
      ]

      query_results = card_id_queries.map do |query|
        query.execute.results.map { |result| result["_id"] }
      end

      matching_ids = query_results.flatten.uniq
      scope = scope.where(id: matching_ids)
    end

    archived_cards = ProjectCardRedactor.new(current_user, scope).cards

    respond_to do |format|
      format.html do
        render partial: "projects/archived_cards_list", locals: {
          project: project,
          cards: archived_cards,
          current_page: current_page,
          next_page: next_archived_cards_page_for(scope, current_page: current_page),
          query: params[:query],
          column_id: params[:column_id],
          filters_present: filters_present,
        }
      end
    end
  end

  def render_check_archived_project_card(project:)
    status = if project.cards.archived.where(id: params[:id]).exists?
      201
    else
      404
    end

    head status
  end

  def render_show_project_card(project:)
    card = this_project.cards.includes(:project).find(params[:id])
    card = ProjectCardRedactor.check_one(current_user, card)
    respond_to do |format|
      format.html do
        render partial: "projects/card", locals: { card: card }
      end
    end
  end

  def update_project_card(project:, repository: nil)
    column = project.columns.find_by_id!(params[:column_id])
    previous_card = column.cards.find_by_id(params[:previous_card_id]) if params[:previous_card_id].present?

    use_automation_behavior = params[:use_automation_prioritization].present?

    # `use_automation_behavior` comes from moving a card triggered from issue/pr sidebar.
    # When this happens, we want it to pass a `position` upon moving the card and respect automation rules.
    position = if !previous_card && use_automation_behavior && !column.automated_with_done_triggers?
      :bottom
    end

    if params[:keyboard_move].present?
      GitHub.dogstats.increment("project.keyboard_move", tags: ["target:card"])
    end

    begin
      if card_id = params[:card_id].presence
        card = project.cards.find(card_id)

        if ProjectCardRedactor.check_one(current_user, card).redacted?
          return head 400
        end

        if card.archived?
          card.unarchive(into_column: column, after: previous_card)
        else
          column.prioritize_card!(card, after: previous_card, new_card: false, position: position)
        end
      else
        content_params = params

        # Check note text for issue references
        references = note_content_references(project: project, note: content_params[:note])
        if references.present?
          # Check if note is a single issue reference already in the project
          card = references.card
          if card && !card.pending?
            return render_note_reference_conflict(project: project, card: card)
          end

          # Convert single issue reference in note to issue-backed card
          GitHub.dogstats.increment("project.convert_note_reference_to_issue_card", tags: [target_tag(project: project)])
          content_params = references.content_params
        end

        if card&.pending?
          column.prioritize_card!(card, after: previous_card, new_card: false, position: position)
        else
          card = ProjectCard.create_in_column(column, creator: current_user, content_params: content_params, after: previous_card, position: position)
        end
      end
    rescue GitHub::Prioritizable::Context::LockedForRebalance
      GitHub.dogstats.increment("project_cards_controller.update.locked_for_rebalance")
      return render status: 503, plain: "Sorry! This column is temporarily locked for maintenance. Please try again."
    end

    unless card.valid?
      return render status: :unprocessable_entity, plain: card.errors.full_messages
    end

    project.reload.notify_subscribers(
      action: "card_update",
      message: "#{current_user} updated a card",
      is_project_activity: card.show_activity?,
    )

    card = ProjectCardRedactor.check_one(current_user, card)

    respond_to do |format|
      format.html do
        render partial: "projects/card", locals: { card: card }
      end
    end
  end

  def stale_note?(card)
    note_version = request.headers["X-Note-Version"]
    note_version && card.note_version != note_version
  end

  def update_project_card_note_task_list(project:)
    card = project.cards.notes.find(params[:id])

    operation = TaskListOperation.from(params[:task_list_operation])
    return head 400 unless operation

    if stale_note?(card)
      render status: :unprocessable_entity, json: {
        stale: true,
        message: "The card you are editing has changed. Please try again.",
      }
    else
      note = operation.call(card.note)
      card.update(note: note) if note
      render json: {
        note: card.note,
        note_version: card.note_version,
      }
    end
  end

  def update_project_card_note(project:)
    unless params[:project_card].is_a?(ActionController::Parameters)
      return head 400
    end

    card = project.cards.notes.find(params[:id])
    if card.update(note: project_card_params[:note])

      respond_to do |format|
        format.html do
          render partial: "projects/card", locals: { card: ProjectCardRedactor.check_one(current_user, card) }
        end
      end
    else
      respond_to do |format|
        format.html do
          render partial: "projects/note_form", locals: { card: ProjectCardRedactor.check_one(current_user, card) }
        end
      end
    end
  end

  ArchiveProjectCardQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectCardId: ID!) {
      archiveProjectCard(input: { projectCardId: $projectCardId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def archive_project_card(project:)
    card = project.cards.find(params[:id])
    variables = { projectCardId: card.global_relay_id }
    mutation = platform_execute(ArchiveProjectCardQuery, variables: variables)

    if mutation.errors.any?
      head 403
    else
      head :ok
    end
  end

  UnarchiveProjectCardQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectCardId: ID!) {
      unarchiveProjectCard(input: { projectCardId: $projectCardId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def unarchive_project_card(project:)
    card = project.cards.find(params[:id])
    variables = { projectCardId: card.global_relay_id }
    platform_execute(UnarchiveProjectCardQuery, variables: variables)

    head :ok
  end

  ConvertProjectCardNoteToIssueQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectCardId: ID!, $repositoryId: ID!, $body: String, $title: String) {
      convertProjectCardNoteToIssue(input: { projectCardId: $projectCardId, repositoryId: $repositoryId, body: $body, title: $title }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def convert_project_card_to_issue(project:, repository:)
    card = project.cards.find(params[:id])

    unless card.is_note?
      card = ProjectCardRedactor.check_one(current_user, card)
      json = {}
      json[:error_code] = :note_already_converted_to_issue
      json[:error_html] = render_to_string partial: "projects/convert_to_issue_error", locals: { card: card }
      return render json: json, status: :conflict
    end

    variables = {
      projectCardId: card.global_relay_id,
      repositoryId: repository.global_relay_id,
      title: params[:title],
      body: params[:body],
    }

    platform_execute(ConvertProjectCardNoteToIssueQuery, variables: variables)

    card.reload
    card = ProjectCardRedactor.check_one(current_user, card)

    respond_to do |format|
      format.html do
        render partial: "projects/card", locals: { card: card }
      end
    end
  end

  def destroy_project_card(project:)
    card = project.cards.find(params[:id])
    card.actor_can_modify_projects(actor: current_user)

    if card.errors.any?
      return render json: { errors: card.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    card.destroy

    card.project.notify_subscribers(
      action: "card_destroy",
      message: "#{current_user} removed a card",
    )

    head :ok
  end

  def preview_project_note(project:, repository: nil)
    references = ProjectCardReferences.new(
      text: params[:note],
      viewer: current_user,
      project: project,
    )

    unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)
    references.filter_unauthorized_orgs(unauthorized_org_ids)
    GitHub.dogstats.count("project.preview_note_references", references.accessible_reference_count, tags: [target_tag(project: project)])

    respond_to do |format|
      format.html do
        render partial: "projects/cards/note_preview", locals: {
          project: project,
          references: references,
        }
      end
    end
  end

  def render_note_reference_conflict(project:, card:)
    respond_to do |format|
      format.html do
        render(
          status: :conflict,
          partial: "projects/cards/note_reference_conflict",
          locals: { card: card },
        )
      end
    end
  end

  def render_pull_request_status(project:)
    pull_request = PullRequest.find(params[:id])
    return render_404 unless pull_request.readable_by?(current_user)

    respond_to do |format|
      format.html do
        view = create_view_model(Statuses::CombinedStatusView, {
          combined_status: pull_request.combined_status,
          simple_view: true,
        })
        render partial: "statuses/combined_branch_status", locals: { view: view }
      end
    end
  end

  def note_content_references(project:, note:)
    references = ProjectCardReferences.new(text: note, project: project, viewer: current_user)
    references if references.can_add_content?
  end

  def card_columns
    return render_404 unless request.xhr?

    card = ProjectCard.find_by_id(params[:id])
    return render_404 unless card

    render "issues/sidebar/project_card_columns_content",
      locals: { project: this_project, card_column: card.column, columns: this_project.columns, card: card },
      layout: false
  end

  def render_project_card_closing_references(project:)
    card = this_project.cards.includes(:project).find(params[:id])
    card = ProjectCardRedactor.check_one(current_user, card)
    return render_404 if card.content.nil? || card.content.pull_request?

    unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: [:saml, :two_factor])

    pull_requests = card.content.closed_by_pull_requests_references_for(
      viewer: current_user,
      unauthorized_organization_ids: unauthorized_org_ids,
    )

    respond_to do |format|
      format.html do
        render partial: "projects/cards/closing_references",
          locals: { card: card, pull_requests: pull_requests }
      end
    end
  end

  def render_project_card_closing_reference(project:)
    card = this_project.cards.includes(:project).find(params[:id])
    card = ProjectCardRedactor.check_one(current_user, card)
    return render_404 if card.content.nil? || card.content.pull_request?

    pull = card.content
      .close_issue_references
      .find_by(pull_request_id: params[:reference_id])
      &.pull_request
    return render_404 if pull.blank? || pull.spammy? || !pull.readable_by?(current_user)
    return render_404 if pull.repository.spammy?
    return render_404 if pull.user&.blocked_by?(current_user)

    respond_to do |format|
      format.html do
        render partial: "projects/cards/closing_reference",
          locals: { card: card, pull_request: pull },
          layout: false
      end
    end
  end

  private

  def next_archived_cards_page_for(archived_cards_scope, current_page:)
    total_matching_archived_cards = archived_cards_scope.limit(nil).offset(nil).count
    total_pages = (total_matching_archived_cards.to_f / ARCHIVED_CARDS_PAGE_SIZE).ceil

    if total_pages > current_page
      current_page + 1
    end
  end

  def project_card_params
    params.require(:project_card).permit :note
  end

  def target_tag(project:)
    case project.owner
    when Repository
      "target:repository"
    when Organization
      "target:organization"
    when User
      "target:user"
    end
  end
end
