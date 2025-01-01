# typed: true
# frozen_string_literal: true

class LabelsController < AbstractRepositoryController
  include LabelEducationHelper
  include Issues::RateLimitsDependency
  include IssuesReactHelper

  before_action :pushers_only, except: [:index, :show]
  before_action :writable_repository_required, except: [:index, :show]
  layout "repository", only: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:preview]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  LABELS_PER_PAGE = 30

  javascript_bundle :"issues-react", only: [:index]

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  rate_limit_requests \
    only: [:index],
    max: ISSUES_BOT_RATE_LIMIT_MAX,
    ttl: 1.minute,
    key: :issues_bot_rate_limit_key,
    if: :issues_bot_rate_limiting_enabled?,
    at_limit: :issues_bot_rate_limit_at_limit

  def index
    return if issue_react_label_index_handler
    query = params[:q]
    ordered_by_count = params[:sort] == "count-asc" || params[:sort] == "count-desc"
    @labels = if query.present?
      search_labels(query)
    else
      list_labels
    end

    unless ordered_by_count
      GitHub::PrefillAssociations.prefill_batch_method(@labels, :batch_issue_counts, current_repository.id) # domain-isolation-query-violation:ignore:packages/issues (select)
    end

    @label = current_repository.labels.new(color: Label.defaults.sample.color)
    render "labels/index", locals: { query: query }
  end

  def create
    name = params[:label][:name]
    color = params[:label][:color]
    description = params[:label][:description]
    path  = gh_labels_path(current_repository)

    color.try(:delete!, "#") # Strip any CSS-style hex codes
    label = current_repository.labels.create(name: name, color: color,
                                             description: description)

    if label.persisted?
      issue_id = params[:issue_id] ? params[:issue_id].to_i : nil
      track_issue_edits_from_project_board(edited_fields: ["labels"])
    end

    respond_to do |wants|
      wants.html do
        if T.must(request).xhr?
          if label.errors.any?
            json = label.errors.as_json(full_messages: true)
            json[:message] = label.errors.full_messages.join(", ")
            render json: json, status: :unprocessable_entity
          elsif params[:return_label_list_item]
            subject_kind = if params[:return_label_list_item] == "discussion"
              :discussion
            else
              :issue
            end

            render partial: "issues/sidebar/label", locals: { label: label, selected: true, subject_kind: subject_kind }
          else
            render partial: "labels/label", object: label
          end
        else
          redirect_to(path)
        end
      end
    end
  end

  def update
    return head(:not_found) unless label = current_repository.labels.find_by_id(params[:id])

    color = params[:label][:color].try(:delete, "#") # Strip any CSS-style hex codes
    label.name = params[:label][:name] if params[:label][:name]
    label.color = color if color
    label.description = params[:label][:description]
    changes = label.changes

    label.save # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    respond_to do |wants|
      wants.html do
        if T.must(request).xhr?
          if label.errors.any?
            json = label.errors.as_json(full_messages: true)
            json[:message] = label.errors.full_messages.join(", ")
            render json: json, status: :unprocessable_entity
          else
            track_issue_edits_from_project_board(edited_fields: ["labels"])
            render partial: "labels/label", object: label
          end
        else
          redirect_to :back
        end
      end
    end
  end

  def destroy
    label = current_repository.labels.find_by_id(params[:id])
    label.destroy if label
    if T.must(request).xhr?
      head(label ? 200 : 404)
    else
      redirect_to :back
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    label = current_repository.labels.find_by_id(params[:id]) if params[:id].present?
    label ||= current_repository.labels.new

    label.name = params[:name]
    label.description = params[:description]
    label.color = params[:color]

    unless label.valid?
      json = label.errors.as_json(full_messages: true)
      json[:message] = label.errors.full_messages.join(", ")
      return render(json: json, status: :unprocessable_entity)
    end

    respond_to do |format|
      format.html do
        render partial: "labels/preview", locals: { label: label }, layout: false
      end
    end
  end

  def show
    if label = current_repository.labels.find_by_name(params[:id])
      redirect_to url_for(controller: :issues, action: :index, labels: label.name)
    else
      render_404
    end
  end

  private

  def list_labels
    case params[:sort]
    when "count-asc"
      labels = labels_by_issues_count("asc")
      labels.paginate(per_page: LABELS_PER_PAGE, page: current_page)
    when "count-desc"
      labels = labels_by_issues_count("desc")
      labels.paginate(per_page: LABELS_PER_PAGE, page: current_page)
    when "name-desc"
      labels = current_repository.sorted_labels.sort_by(&:name).reverse
      labels.paginate(per_page: LABELS_PER_PAGE, page: current_page)
    else
      params[:sort] = "name-asc"
      labels = current_repository.sorted_labels
      labels.paginate(per_page: LABELS_PER_PAGE, page: current_page)
    end
  end

  def labels_by_issues_count(order)
    subquery_for_counts =
      Issue
        .where(repository: current_repository, state: "open")
        .joins(:issues_labels)
        .select(
          :label_id,
          Arel.sql("COUNT(issues.id) as issues_count"),
          Arel.sql("COUNT(issues.id) - COUNT(issues.pull_request_id) as issues_without_pull_requests_count"))
        .group(:label_id)

    labels = Label
      .select(Arel.sql("labels.*"),
        Arel.sql("IFNULL(label_counts.issues_count, 0) as issues_count"),
        Arel.sql("IFNULL(label_counts.issues_without_pull_requests_count, 0) as issues_without_pull_requests_count"))
      .joins("LEFT OUTER JOIN (#{subquery_for_counts.to_sql}) AS label_counts ON labels.id = label_counts.label_id")
      .where(repository: current_repository)

    # We do in memory sorting here to replicate the old way of sorting (using BranchSorter), as the comparison against
    # issues count, version number and then name is too complex to effectively do within a SQL query.
    labels = labels.sort do |left, right| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      result = left.issues_count <=> right.issues_count
      next result unless result.zero?
      BranchSorter.compare(left.name, right.name)
    end

    labels.reverse! if order == "desc"
    labels
  end

  def search_labels(query)
    search_helper = Search::QueryHelper.new(query, "Labels", current_user: current_user,
                                            repo_id: current_repository.id, page: current_page,
                                            per_page: LABELS_PER_PAGE, remote_ip: T.must(request).remote_ip)
    search_results = search_helper.current.execute
    WillPaginate::Collection.create(current_page, LABELS_PER_PAGE) do |pager|
      pager.replace(search_results.map(&:label))
      pager.total_entries ||= search_results.total_entries
    end
  end
end
