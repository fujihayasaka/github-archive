# typed: true
# frozen_string_literal: true

class CommunityController < AbstractRepositoryController
  layout "repository"
  javascript_bundle :community
  stylesheet_bundle :insights

  include PlatformHelper

  before_action :login_required, except: :index
  before_action :ask_the_gatekeeper
  before_action :non_forks_only, except: [:license_tool, :code_of_conduct_tool, :minimize_comment, :unminimize_comment]
  before_action :render_404, unless: :community_profile_enabled?, except: [:minimize_comment, :unminimize_comment]
  before_action :enforce_plan_supports_insights, only: :index

  rescue_from Platform::Errors::NotFound, with: :render_404

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:code_of_conduct_tool]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:license_tool]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :code_of_conduct_tool, :license_tool], optional: true

  def index
    return render_404 unless current_repository.public?

    view = create_view_model(
      Community::CommunityIndexView,
      community_profile: community_profile,
      repository: current_repository,
    )
    render "/community/index", locals: { view: view }
  end

  def minimize_comment # rubocop:todo GitHub/UseRestfulActions
    comment = find_comment
    success = false

    if comment.async_minimizable_by?(current_user).sync
      success = comment.set_minimized(current_user, nil, params[:classifier], comment.user || User.ghost)
    end

    if success
      if request.xhr?
        head :ok
      else
        redirect_to :back
      end
    else
      respond_to do |format|
        format.json do
          render json: { error: "could not minimize comment" }, status: :forbidden
        end
        format.all do
          render plain: "could not minimize comment", status: :forbidden
        end
      end
    end
  end

  def unminimize_comment # rubocop:todo GitHub/UseRestfulActions
    comment = find_comment
    success = false

    if comment.async_unminimizable_by?(current_user).sync
      success = comment.set_unminimized(current_user, nil, comment.user || User.ghost)
    end

    if success
      if request.xhr?
        head :ok
      else
        redirect_to :back
      end
    else
      respond_to do |format|
        format.json do
          render json: { error: "could not unminimize comment" }, status: :forbidden
        end
        format.all do
          render plain: "could not unminimize comment", status: :forbidden
        end
      end
    end
  end

  # See Coconductor::Field.all.map(&:key) for a list of valid fields
  def code_of_conduct_tool # rubocop:todo GitHub/UseRestfulActions
    code_of_conduct = params[:template] ? CodeOfConduct.find_by_key(params[:template]) : nil
    owner = current_repository.owner
    render "/community/add_code_of_conduct", locals: {
      code_of_conduct: code_of_conduct,
      community_name: current_repository.name.titleize,
      email_address: owner.publicly_visible_email(logged_in: true),
      contact_info: owner.publicly_visible_email(logged_in: true),
      governing_body: (owner if owner.organization?),
    }
  end

  def license_tool # rubocop:todo GitHub/UseRestfulActions
    if params[:template]
      @license = License.find(params[:template])
    else
      @license = nil
    end

    render "community/add_license", locals: { license: @license }
  end

  private

  def community_profile
    current_repository.community_profile || CommunityProfile.new(repository_id: current_repository.id)
  end

  def non_forks_only
    render_404 if current_repository.fork?
  end

  def community_profile_enabled?
    GitHub.community_profile_enabled?
  end

  def find_comment
    typed_object_from_id([Platform::Interfaces::Comment], params.fetch(:comment_id))
  end

  def route_supports_advisory_workspaces?
    case action_name
    when "minimize_comment", "unminimize_comment"
      true
    else
      false
    end
  end
end
