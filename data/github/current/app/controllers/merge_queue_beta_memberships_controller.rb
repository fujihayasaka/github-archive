# typed: true
# frozen_string_literal: true

class MergeQueueBetaMembershipsController < ApplicationController
  include AccountMembershipHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:signup]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:signup],
    optional: true

  EARLY_ACCESS_FEATURE_SLUG = "merge_queue"

  before_action :dotcom_required
  before_action :login_required

  def signup # rubocop:todo GitHub/UseRestfulActions
    render "merge_queue_beta/signup"
  end
end
