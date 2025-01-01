# typed: true
# frozen_string_literal: true

class Stafftools::GhasCommittersController < StafftoolsController
  before_action :enterprise_required

  track_latency_slo "p99-ui-request", 2000
  track_latency_slo "p50-ui-request", 500
  track_availability_slo "ui-request"

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :download_active_committers, :download_maximum_committers]

  def index
    render "stafftools/ghas_committers/index"
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: GitHub.global_business, committer_type: :ACTIVE_COMMITTERS),
      filename: "ghas_active_committers_#{GitHub.global_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: GitHub.global_business, committer_type: :MAXIMUM_COMMITTERS),
      filename: "ghas_maximum_committers_#{GitHub.global_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end
end
