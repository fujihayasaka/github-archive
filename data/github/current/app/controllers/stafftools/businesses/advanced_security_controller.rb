# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::AdvancedSecurityController < Stafftools::Businesses::BusinessBaseController
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:download_active_committers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:download_maximum_committers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:download_ghas_repositories]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    skus = [GitHub::Turboghas::SKU::Bundled]
    if !this_business.advanced_security_products_bundled?
      skus = [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity]
    end

    render "stafftools/businesses/advanced_security/show", locals: {
      skus:,
    }
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :ACTIVE_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])), filename: "ghas_active_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :MAXIMUM_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])), filename: "ghas_maximum_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_ghas_repositories # rubocop:todo GitHub/UseRestfulActions
    sku = GitHub::Turboghas::SKU.from_param(params[:sku])
    cursor = T.let(nil, T.nilable(Turboghas::Proto::Cursor))
    csv = CSV.generate do |row|
      row << ["Organization / repository"]
      loop do
        data = GitHub::Turboghas.check_error(T.let(GitHub::Turboghas.client.get_enabled_repositories({ entity_id: this_business.id, entity_type: :ENTITY_TYPE_BUSINESS, cursor: cursor, features: sku.features }), Twirp::ClientResp[::Turboghas::Proto::GetEnabledRepositoriesResponse]))
        data.repositories.each do |repo|
          row << [repo.name_with_display_owner]
        end
        break if data.next_cursor.blank?
        cursor = data.next_cursor
      end
    end

    send_data csv, filename: "ghas_repositories_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end
end
