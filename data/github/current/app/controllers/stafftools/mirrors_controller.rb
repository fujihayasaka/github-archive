# typed: true
# frozen_string_literal: true

class Stafftools::MirrorsController < StafftoolsController
  before_action :ensure_repo_exists
  after_action :clear_gitkeeper_cache, only: :create

  def create
    mirror = current_repository.build_mirror(url: params["mirror_url"])
    if mirror.valid?
      mirror.save
      mirror.perform
      flash[:notice] = "Mirror was successfully created and queued for sync."
    else
      flash[:error] = mirror.errors.full_messages.to_sentence
    end
    redirect_to :back
  end

  def update
    mirror = current_repository.mirror
    mirror.url = params["mirror_url"]
    if mirror.save
      mirror.perform
      flash[:notice] = "Mirror was successfully updated and queued for sync."
    else
      flash[:error] = mirror.errors.full_messages.to_sentence
    end

    redirect_to :back
  end

  def sync # rubocop:todo GitHub/UseRestfulActions
    mirror = current_repository.mirror
    mirror.perform

    flash[:notice] = "Mirror queued for sync."
    redirect_to :back
  end

  def destroy
    mirror = current_repository.mirror
    mirror.destroy
    instrument("staff.disable_mirroring",
                user: current_repository.owner,
                repo: current_repository)

    flash[:notice] = "Mirroring removed."
    redirect_to :back
  end

  private

  def clear_gitkeeper_cache
    # update the updated_at column to bust the cache
    current_repository.touch
  end
end
