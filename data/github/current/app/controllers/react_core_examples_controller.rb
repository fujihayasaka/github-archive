# typed: true
# frozen_string_literal: true

require "react_payload"

class ReactCoreExamplesController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:mutations_update]

  before_action :require_feature_flags, :add_client_feature_flags
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Repositories,
  ApplicationRecord::Ballast,
  ApplicationRecord::IssuesPullRequests,
  only: [
    :index,
    :dependent_data,
    :dependent_data_deferred,
    :enriched_data,
    :enriched_data_deferred,
    :feature_flag,
    :live_data,
    :mutations,
    :pagination_deferred,
    :pagination,
    :shared_components,
  ]

  def index
    respond_with_react(
      title: "Home - React Core Examples",
      payload: IndexRoutePayload.new,
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      title: nil,
      payload: LayoutRoutePayload.new(user: current_user),
    )
  end

  def dependent_data # rubocop:todo GitHub/UseRestfulActions
    user = if params[:login]
      User.find_by_login(params[:login])
    else
      current_user
    end

    respond_with_react(
      title: "Dependent Data - React Core Examples",
      payload: DependentDataRoutePayload.new(user: user_payload(user)),
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def dependent_data_deferred # rubocop:todo GitHub/UseRestfulActions
    # simulate some latency, this will take 1-3 seconds
    sleep 1 + (2 * rand)
    render json: issues_payload
  end

  def enriched_data # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      title: "Enriched Data - React Core Examples",
      payload: EnrichedDataRoutePayload.new(
        user: user_payload(current_user),
        pulls: pulls_payload,
      ),
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def enriched_data_deferred # rubocop:todo GitHub/UseRestfulActions
    sleep 1 + (2 * rand)
    render json: pull_labels_payload
  end

  def feature_flag # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      title: "ReactCoreExamples Feature Flagged Route",
      payload: FeatureFlagRoutePayload.new,
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def live_data # rubocop:todo GitHub/UseRestfulActions
    pull = Issue.where(user_id: user_id, has_pull_request: true, state: "open").order(created_at: :asc).last # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    respond_with_react(
      title: "ReactCoreExamples Live Data",
      payload: LiveDataRoutePayload.new(pull),
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def mutations # rubocop:todo GitHub/UseRestfulActions
    mutations_route_payload = MutationsRoutePayload.new(user_status: current_user.user_status_when_not_expired)

    respond_with_react(
      title: "Mutations - React Core Examples",
      payload: MutationsRoutePayload.new(user_status: current_user.user_status_when_not_expired),
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def mutations_update # rubocop:todo GitHub/UseRestfulActions
    # return render(status: 500, json: { message: "This action randomly fails 25% of the time" }) if rand(1..4) == 1

    expires_at = params[:expires_at]

    if expires_at.present?
      expires_at = begin
        Time.iso8601(expires_at)
      rescue ArgumentError, ::TypeError
        nil
      end
    end

    input = {
      message: params[:message].presence,
      emoji: params[:emoji].presence,
      expires_at: expires_at,
      limited_availability: params[:limited_availability] == "1",
    }

    status = begin
      UserStatus.set_for(current_user, **input)
      :ok
    rescue ActiveRecord::RecordNotFound
      :unprocessable_entity
    end

    current_user.reload_user_status # Ensure latest status is used
    mutations_route_payload = MutationsRoutePayload.new(user_status: current_user.user_status_when_not_expired)

    render json: mutations_route_payload.payload, status: status
  end

  def pagination # rubocop:todo GitHub/UseRestfulActions
    pagination_route_payload = PaginationRoutePayload.new(
      user: current_user,
      count: Issue.where(user_id: user_id, has_pull_request: false, state: "open").count, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    )

    respond_with_react(
      title: "Pagination - React Core Examples",
      payload: PaginationRoutePayload.new(
        user: current_user,
        count: Issue.where(user_id: user_id, has_pull_request: false, state: "open").count, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      ),
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def pagination_deferred # rubocop:todo GitHub/UseRestfulActions
    sleep 1 + (2 * rand)
    render json: issues_payload
  end

  def shared_components # rubocop: todo  GitHub/UseRestfulActions
    shared_components_payload = SharedComponentsRoutePayload.new(user_status: current_user.user_status_when_not_expired)

    respond_with_react(
      title: "Shared Components – React Core Examples",
      payload: SharedComponentsRoutePayload.new(user_status: current_user.user_status_when_not_expired),
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def nested_render_error # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      title: "Nested RenderError - React Core Examples",
      payload: NestedRenderErrorRoutePayload.new,
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  def nested_loader_error # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      title: "Nested Loader Error - React Core Examples",
      payload: NestedLayoutErrorRoutePayload.new,
      nested_payloads: -> { [
        LayoutRoutePayload.new(user: current_user),
      ]
      },
    )
  end

  private

  class IndexRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesIndexRoute"
    end

    def payload
      {}
    end
  end

  class LayoutRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesLayoutRoute"
    end

    sig { params(user: User).void }
    def initialize(user:)
      @user = user
    end

    def payload
      {
        login: @user.display_login
      }
    end
  end

  class DependentDataRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesDependentDataRoute"
    end

    sig { params(user: T.nilable(Hash)).void }
    def initialize(user:)
      @user = user
    end

    def payload
      if @user
        {
          **@user
        }
      end
    end
  end

  class EnrichedDataRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesEnrichedDataRoute"
    end

    sig { params(user: T.nilable(Hash), pulls: Hash).void }
    def initialize(user:, pulls:)
      @user = user
      @pulls = pulls
    end

    def payload
      {
        user: @user,
        **@pulls
       }
    end
  end

  class FeatureFlagRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesFeatureFlagRoute"
    end

    def payload
      {}
    end
  end

  class LiveDataRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesLiveDataRoute"
    end


    sig { params(pull: T.nilable(Issue)).void }
    def initialize(pull)
      @pull = pull
      @alive_channel = ::GitHub::WebSocket::Channels.signed_pull_request(pull)
    end

    def payload
      return nil unless @pull
      {
        aliveChannel: @alive_channel,
        pull: {
          id: @pull.id,
          title: @pull.title,
          url: @pull.url(include_host: false),
          labels: labels
        }
      }
    end

    private

    def labels
      return [] unless @pull
      @pull.labels.map do |label|
        {
          id: label.id,
          name: label.name,
          nameHTML: label.name_html,
          color: label.color,
          url: label.url,
          description: label.description,
        }
      end
    end
  end

  class MutationsRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesMutationsRoute"
    end

    sig { params(user_status: T.nilable(UserStatus)).void }
    def initialize(user_status:)
      @user_status = user_status
    end

    def payload
      {
        userStatus: user_status,
      }
    end

    private

    def user_status
      return nil unless @user_status
      {
        emoji: @user_status["emoji"],
        expiresAt: @user_status["expires_at"],
        limitedAvailability: @user_status["limited_availability"],
        message: @user_status["message"],
      }
    end
  end

  class PaginationRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesPaginationRoute"
    end

    sig { params(user: User, count: Integer).void }
    def initialize(user:, count:)
      @user = user
      @count = count
    end

    def payload
      {
        login: @user.display_login,
        count: @count,
       }
    end
  end

  class SharedComponentsRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesSharedComponentsRoute"
    end

    sig { params(user_status: T.nilable(UserStatus)).void }
    def initialize(user_status:)
      @user_status = user_status
    end

    def payload
      {
        userStatus: user_status,
      }
    end

    private

    def user_status
      return nil unless @user_status
      {
        emoji: @user_status["emoji"],
        expiresAt: @user_status["expires_at"],
        limitedAvailability: @user_status["limited_availability"],
        message: @user_status["message"],
      }
    end
  end

  class NestedRenderErrorRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesNestedRenderErrorRoute"
    end

    def payload
      {}
    end
  end

  class NestedLayoutErrorRoutePayload < ReactPayload::Base
    def route_id
      "reactCoreExamplesNestedLayoutErrorRoute"
    end

    def payload
      {}
    end
  end

  def issues_payload
    state = params[:state] || :open
    page = params[:page] || 1
    per_page = 10

    {
      issues: Issue.where(user_id: user_id, has_pull_request: false, state: state).paginate(page: page, per_page: per_page).map do |issue|
        {
          id: issue.id,
          title: issue.title,
          url: issue.url(include_host: false),
          state: issue.state
        }
      end
    }
  end

  def pulls_payload
    state = params[:state] || :open
    page = params[:page] || 1
    per_page = 10

    {
      pulls: Issue.where(user_id: user_id, has_pull_request: true, state: state).paginate(page: page, per_page: per_page).map do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        {
          id: issue.id,
          title: issue.title,
          url: issue.url(include_host: false),
          state: issue.state
        }
      end
    }
  end

  def pull_labels_payload
    state = params[:state] || :open
    page = params[:page] || 1
    per_page = 10

    {
      pulls: Issue.where(user_id: user_id, has_pull_request: true, state: state).paginate(page: page, per_page: per_page).map do |issue|
        {
          id: issue.id,
          labels: issue.labels.map do |label|
            {
              id: label.id,
              name: label.name,
              color: label.color,
            }
          end
        }
      end
    }
  end

  def user_payload(user)
    if user
      {
        id: user.id,
        login: user.display_login,
        avatarUrl: user.primary_avatar_url(40),
      }
    else
      {
        id: nil,
        login: nil,
        avatarUrl: nil,
      }
    end
  end

  def user_id
    params[:user_id] || current_user.id
  end

  def set_default_nav_breadcrumb
    set_nav_breadcrumb ContextRegion::ReactCoreExamplesCrumb.new
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_feature_flags
    render_404 unless current_user&.feature_enabled?(:react_core_examples)
  end

  def add_client_feature_flags
    add_client_feature_flag([:react_core_examples_feature_flag])
  end
end
