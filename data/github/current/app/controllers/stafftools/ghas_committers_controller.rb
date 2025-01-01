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
    skus = [GitHub::Turboghas::SKU::Bundled]
    unless GitHub.global_business.advanced_security_products_bundled?
      skus = [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity]
    end

    render "stafftools/ghas_committers/index", locals: { skus: skus }
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: GitHub.global_business, committer_type: :ACTIVE_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])),
      filename: "ghas_active_committers_#{GitHub.global_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: GitHub.global_business, committer_type: :MAXIMUM_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])),
      filename: "ghas_maximum_committers_#{GitHub.global_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end
end
