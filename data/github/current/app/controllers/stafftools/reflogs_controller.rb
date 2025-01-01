# typed: true
# frozen_string_literal: true

class Stafftools::ReflogsController < StafftoolsController

  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/security"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    @ref = params[:ref]
    page = params[:page]
    @entries = []

    if current_repository.online?
      # Supportocats may specify one of around_oid|around_before_oid|around_after_oid to
      # jump to the spot in the reflog where a particular oid was pushed to and/or from.
      if around_oid = params[:around_oid]
        around = { before: around_oid, after: around_oid }
      elsif around_oid = params[:around_before_oid]
        around = { before: around_oid }
      elsif around_oid = params[:around_after_oid]
        around = { after: around_oid }
      else
        around = {}
      end

      if around.any?
        log = []
        log += current_repository.reflog(@ref, squash: true, limit: 1, before_oid: around_oid) if around[:before]
        log += current_repository.reflog(@ref, squash: true, limit: 1, after_oid: around_oid) if around[:after]

        if log.empty?
          flash[:notice] = "No matching entries for #{around_oid}"
        else
          flash[:notice] = "Found entries around #{around_oid}"
          starting_point = log.map { |ent| ent.time.to_i }.max + 1
          redirect_to url_with(
            ref: @ref,
            older_than: starting_point,
            around_oid: nil,
            around_before_oid: nil,
            around_after_oid: nil,
          )
        end
      else
        options = { squash: true, page: page }
        options[:newer_than] = params[:newer_than] if params[:newer_than]
        options[:older_than] = params[:older_than] if params[:older_than]
        options[:before_oid] = params[:before_oid] if params[:before_oid]
        options[:after_oid]  = params[:after_oid]  if params[:after_oid]
        @entries = current_repository.reflog(@ref, options)
      end
    else
      flash[:error] = "Repository offline, cannot get push log"
    end

    render "stafftools/reflogs/show" unless performed?
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    oid = params[:oid]
    name = params[:ref]
    name += "-recovery-#{oid[0..6]}" if current_repository.heads.include?(name)
    human_name = name.gsub /\Arefs\/heads\//, ""

    if current_repository.heads.include?(name)
      flash[:error] = "Restoration branch '#{human_name}' already exists"
    else
      actor = User.find_by_login(GitHub.mirror_pusher.to_s) if GitHub.mirror_pusher
      actor ||= current_user

      current_repository.heads.create(name, oid, actor,
                                      reflog_data: request_reflog_data("stafftools branch restore"))

      flash[:notice] = "Restored branch '#{human_name}' at #{oid[0..6]}"
    end

    redirect_to :back
  end

  def deleted # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/reflogs/deleted"
  end

  def force_pushes # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/reflogs/force_pushes"
  end

  def index
    render "stafftools/reflogs/index"
  end

  private

  def request_reflog_data(via)
    {
      real_ip: request.remote_ip,
      repo_name: current_repository.name_with_owner,
      user_login: current_user.login,
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: via,
    }
  end

end
