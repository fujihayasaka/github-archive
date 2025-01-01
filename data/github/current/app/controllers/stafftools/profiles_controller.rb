# typed: true
# frozen_string_literal: true

class Stafftools::ProfilesController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  layout "layouts/stafftools/user/overview"

  before_action :ensure_user_exists
  before_action :dotcom_required

  def show
    render Stafftools::Users::ProfileComponent.new(user: this_user, nodeinfo_cache_values:)
  end

  def recalculate_all # rubocop:todo GitHub/UseRestfulActions
    user_metadata_updater.trigger_recalculation!(attribute_to_recalculate: "all")

    flash[:notice] = "User metadata is being recalculated, this may take some time."
    redirect_to :back
  end

  def recalculate_attribute # rubocop:todo GitHub/UseRestfulActions
    user_metadata_updater.trigger_recalculation!(attribute_to_recalculate: attribute)

    flash[:notice] = "#{attribute} is being recalculated, this may take some time."
    redirect_to :back
  end

  def toggle_attribute # rubocop:todo GitHub/UseRestfulActions
    if user_metadata_updater.toggle!(attribute_to_toggle: attribute)
      flash[:notice] = "#{attribute} has been toggled."
      redirect_to :back
    else
      flash[:error] = "There was a problem toggling #{attribute}, please try again later."
      redirect_to :back
    end
  end

  private

  def attribute
    params[:attribute]
  end

  memoize def user_metadata_updater
    Stafftools::UserMetadataUpdater.new(user: this_user)
  end

  memoize def nodeinfo_cache_values
    accounts_by_key = Hash.new { |h, k| h[k] = [] }
    Array(this_user.profile_social_accounts).each do |account|
      next unless account.needs_nodeinfo_recognition?

      host = account.url_host
      next unless host

      key = SocialAccounts::NodeinfoProbe.kv_cache_key(host)
      next unless key

      accounts_by_key[key] << account
    end

    all_keys = accounts_by_key.keys
    return {} if all_keys.empty?

    all_values = Profiles::Kv.store.mget(all_keys).value { [] }
    accounts_and_values = all_keys.zip(all_values).flat_map do |(key, value)|
      next [] unless value.present?

      accounts_by_key[key].map { |account| [account, value] }
    end
    accounts_and_values.to_h
  end
end
