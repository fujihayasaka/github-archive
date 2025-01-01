# typed: true
# frozen_string_literal: true

class Site::AboutController < Site::About::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  def index
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled_or_raise?(:contentful_lp_about, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    render "site/about/index"
  end
end
