# typed: true
# frozen_string_literal: true

class Stafftools::Users::RenamesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :overview_layout

  def create
    login = params[:login]
    old_name = this_user.login

    if this_user.rename(
      login,
      actor: current_user,
      rename_reason: params[:reason],
      rename_notes: params[:notes],
    )
      if !GitHub.enterprise?
        dormancy_status = this_user.dormancy_status

        GitHub.logger.info(
          "code.namespace" => "Stafftools::Users::RenamesController",
          "code.function" => "create",
          "gh.actor.id" => this_user.id,
          "gh.rename.notes" => params[:notes],
          "gh.rename.reason" => params[:reason],
          "gh.rename.dormant" => dormancy_status[:dormant],
          "gh.rename.active_keys" => dormancy_status[:active_keys],
        )

        tags = [
          "reason:#{params[:reason]}",
          "dormant:#{dormancy_status[:dormant]}",
          "#account_type:#{this_user.type}",
        ]
        dormancy_status[:active_keys].each { |key| tags.push("#{key}:active_value") }
        dormancy_status[:ignored].each { |key, value| tags.push("#{key}:#{value}") }
        GitHub.dogstats.increment("stafftools_account_rename", tags: tags)
      end

      render(
        "stafftools/users/renames/create",
        locals: { user: this_user, new_login: login, old_login: old_name },
      )
    else
      flash[:error] = this_user.errors.full_messages.to_sentence

      redirect_to stafftools_user_administrative_tasks_path(this_user)
    end
  end
end
