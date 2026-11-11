# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::LabelsController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:index, :create]

  before_action :parse_json_params
  before_action :validate_index_params, only: [:index]
  before_action :validate_create_params, only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:index, :create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Ghui::ItemPickers::LabelsController#create"].freeze

  # the data that is selected via this GraphQL query must be kept in sync with the frontend part
  # that lives in github-ui/packages/item-picker-label-tsq/api/label.ts
  QUERY = <<-'GRAPHQL'
    query($owner: String!, $repo: String!, $count: Int!, $query: String = "", $labelNames: String = "", $shouldQueryByNames: Boolean = false) {
      repository(owner: $owner, name: $repo) {
        id
        labels(first: $count, query: $query, orderBy: {field: NAME, direction: ASC}) {
        totalCount
        nodes {
            id
            color
            name
            nameHTML
            description
            url
          }
        }
        labelsByNames: labels(names: $labelNames, first: $count, orderBy: {field: NAME, direction: ASC})
          @include(if: $shouldQueryByNames) {
          nodes {
            id
            color
            name
            nameHTML
            description
            url
          }
        }
      }
    }
  GRAPHQL

  def index
    count = parse_integer_param(:count, default: 100)
    count = [[count, 1].max, 1000].min # clamp between 1 and 1000

    if repository && !params[:query].present? && !params[:labelNames].present?
      index_with_active_record(count)
    else
      index_with_graphql([count, 100].min)
    end
  end

  # the data that is selected via this GraphQL query must be kept in sync with the frontend part
  # that lives in github-ui/packages/item-picker-label-tsq/api/label.ts
  CREATE_MUTATION = <<-'GRAPHQL'
    mutation($input: CreateLabelInput!) {
      createLabel(input: $input) {
        label {
          id
          color
          name
          nameHTML
          description
          url
        }
      }
    }
  GRAPHQL

  def create
    results = execute_graphql(CREATE_MUTATION, "createLabel", variables: {
      "input" => {
        "repositoryId" => params[:repositoryId],
        "color" => params[:color],
        "name" => params[:name],
      }
    })

    respond_graphql_payload(results)
  end

  private

  def index_with_graphql(count)
    should_query_by_names = params[:labelNames].present?

    results = execute_graphql(QUERY, "searchLabels", variables: {
      owner: params[:owner],
      repo: params[:repo],
      query: params[:query],
      labelNames: params[:labelNames],
      count: count,
      shouldQueryByNames: should_query_by_names
    })

    respond_graphql_payload(results)
  end

  def index_with_active_record(count)
    repo = T.must(repository)

    unless repo.readable_by?(current_user)
      owner_login = params[:owner]
      repo_name = params[:repo]
      respond_payload({ errors: [{ message: "Could not resolve to a Repository with the name '#{owner_login}/#{repo_name}'." }] })
      return
    end

    labels_scope = repo.labels.order(name: :asc)
    total_count = labels_scope.count
    label_nodes = serialize_labels(labels_scope.limit(count))

    respond_payload({
      data: {
        repository: {
          id: repo.global_relay_id,
          labels: {
            totalCount: total_count,
            nodes: label_nodes,
          },
        },
      },
    })
  end

  def serialize_labels(labels)
    labels.map do |label|
      {
        id: label.global_relay_id,
        color: label.color,
        name: label.name,
        nameHTML: label.name_html,
        description: label.description,
        url: label.url,
      }
    end
  end

  def validate_index_params
    return unless validate_required_params(:owner, :repo)
    return unless validate_integer_param(:count)

    # Check that query and labelNames are not both provided
    if params[:query].present? && params[:labelNames].present?
      respond_error(:bad_request, "Cannot provide both query and labelNames parameters")
      return false
    end

    true
  end

  def validate_create_params
    validate_required_params(:repositoryId, :color, :name)
  end

  memoize def owner
    User.find_by_login(params[:owner])
  end

  memoize def repository
    return nil unless owner && params[:repo]
    Repositories.domain.by_name_and_owner(name: params[:repo], owner_id: owner.id, cached: true)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repository
  end

  def target_for_conditional_access
    owner
  end
end
