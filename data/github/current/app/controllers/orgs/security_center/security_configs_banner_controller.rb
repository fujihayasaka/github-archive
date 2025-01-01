# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityConfigsBannerController < Orgs::Controller
  extend T::Sig

  # Access
  before_action :organization_read_required

  sig { void }
  def destroy
    cache_key = ::SecurityCenter::SecurityConfigsBannerComponent.dismissal_key(user_id: current_user.id)
    SecurityCenter::KV.store.set(cache_key, "true")

    redirect_to(:back)
  end
end
