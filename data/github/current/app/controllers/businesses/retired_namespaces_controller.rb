# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/DoNotAllowOwnerLogin

class Businesses::RetiredNamespacesController < Businesses::BusinessController
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Authnd,
    only: [:index]

  PER_PAGE = 25

  def index
    return render_404 unless GitHub.multi_tenant_enterprise?

    distinct_owners = RetiredNamespace.select(:owner_login).distinct.pluck(:owner_login)
    relevant_distinct_owners = distinct_owners.filter { |owner_login| owner_login.end_with?("_" + this_business.shortcode) }
    retired_namespaces = RetiredNamespace.where(owner_login: relevant_distinct_owners)

    if params[:query].present?
      retired_namespaces = retired_namespaces.where("concat(replace(owner_login, ?, ''), '/', name) like ?", "_" + this_business.shortcode, "%#{params[:query]}%")
    end

    retired_namespaces = retired_namespaces.order(owner_login: :asc, name: :asc).paginate(
      page: current_page,
      per_page: PER_PAGE,
    )

    if request.xhr?
      render partial: "businesses/settings/retired_namespaces/list", locals: { retired_namespaces: retired_namespaces }
    else
      render "businesses/settings/retired_namespaces/index", locals: { retired_namespaces: retired_namespaces }
    end
  end

  def destroy
    return render_404 unless GitHub.multi_tenant_enterprise?

    retired_namespace = RetiredNamespace.find_by(id: params[:id])
    return render_404 unless retired_namespace.present?
    return render_404 unless T.must(retired_namespace.owner_login).end_with?("_" + this_business.shortcode)

    result = retired_namespace.unretire

    if result.success?
      flash[:notice] = "Unretired #{retired_namespace.name_with_display_owner}"
    else
      flash[:error] = "Unretiring namespace failed: #{result.errors.to_sentence}"
    end

    redirect_to settings_retired_namespaces_enterprise_path(this_business.slug)
  end
end
