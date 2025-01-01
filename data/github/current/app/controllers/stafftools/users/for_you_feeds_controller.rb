# typed: true
# frozen_string_literal: true

class Stafftools::Users::ForYouFeedsController < StafftoolsController

  before_action :ensure_user_exists
  before_action :require_conduit_feed_enabled?

  def destroy
    begin
      Conduit::KVBackedCache.invalidate_for(this_user)
      flash[:notice] = "Cleared For You feed cache for #{this_user}"
    rescue Conduit::KVBackedCache::CacheUnavailableError
      flash[:error] = "Could not clear For You feed cache for #{this_user}"
    end

    redirect_to stafftools_user_path(this_user)
  end

  private

  def require_conduit_feed_enabled?
    render_404 unless GitHub.conduit_feed_enabled?
  end
end
