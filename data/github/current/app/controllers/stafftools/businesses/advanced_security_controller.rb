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

    transition = ::Licensing::GhasUnbundleTransition.where(customer_id: this_business.customer_id).last

    render "stafftools/businesses/advanced_security/show", locals: {
      skus:,
      transition:,
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
        req = Turboghas::Proto::GetEnabledRepositoriesRequest.new(entity_id: this_business.id, entity_type: :ENTITY_TYPE_BUSINESS, cursor: cursor, features: sku.features)
        data = GitHub::Turboghas.check_error(GitHub::Turboghas.client.get_enabled_repositories(req))
        data.repositories.each do |repo|
          row << [repo.name_with_display_owner]
        end
        break if data.next_cursor.blank?
        cursor = data.next_cursor
      end
    end

    send_data csv, filename: "ghas_repositories_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def create_sku_transition # rubocop:disable GitHub/UseRestfulActions
    # Check for earlier transitions on the same date, to ensure we're not trying to create duplicate records
    customer = T.must(this_business.customer)
    transition_date = params[:transition_date].presence || Date.current
    target_sku_state = params[:target_sku_state] || "unbundled"

    transition = ::Licensing::GhasUnbundleTransition.find_by(customer: customer, transition_date: transition_date)

    if transition.present?
      transition.update!(status: "scheduled", target_sku_state: target_sku_state)
    else
      transition = ::Licensing::GhasUnbundleTransition.new(
        customer: T.must(this_business.customer),
        transition_date: params[:transition_date].presence || Date.current,
        status: "scheduled",
        actor: current_user,
        target_sku_state: params[:target_sku_state] || "unbundled"
      )
      transition.save!
    end

    if T.must(transition).transition_date == Date.current
      T.must(transition).enqueue
      flash[:notice] = "This enterprise will now transition to #{T.must(transition).target_sku_state} SKU(s). This could take a while for larger accounts."
    else
      flash[:notice] = "This enterprise will transition to #{T.must(transition).target_sku_state} SKU(s) on #{T.must(transition).date}."
    end

    redirect_to stafftools_advanced_security_path(this_business)
  end

  def cancel_sku_transition # rubocop:disable GitHub/UseRestfulActions
    transition = ::Licensing::GhasUnbundleTransition.find(params[:transition_id])

    transition.cancel!

    flash[:notice] = "Transition to #{transition.target_sku_state} SKU(s) scheduled for #{transition.date} has been cancelled."

    redirect_to stafftools_advanced_security_path(this_business)
  end
end
