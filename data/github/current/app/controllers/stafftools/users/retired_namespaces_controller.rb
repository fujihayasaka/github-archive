# typed: true
# frozen_string_literal: true

class Stafftools::Users::RetiredNamespacesController < Stafftools::UsersController
  before_action :ensure_this_namespace, only: :destroy
  skip_before_action :enterprise_required
  skip_before_action :ensure_user_exists

  layout :retired_namespaces_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  PER_PAGE = 100

  def index
    namespaces = RetiredNamespace.for_owner(namespace_owner).reorder(created_at: :desc).paginate(
      page: current_page,
      per_page: PER_PAGE,
    )
    audit_log_queries = {}
    namespaces.each do |namespace|
      action = "where action in ('user.rename', 'user.delete', 'user.async_delete', 'org.rename', 'org.delete', 'org.async_delete')"
      timestamp_range = "where _timestamp >= datetime_add('second',-1,datetime('#{namespace.created_at}')) | where _timestamp <= datetime_add('second',1,datetime('#{namespace.created_at}'))"
      audit_log_query = "webevents | #{timestamp_range} | #{action}"
      audit_log_queries[namespace.id] = audit_log_query
    end

    render "stafftools/users/retired_namespaces", locals: {
      namespaces: namespaces,
      owner: namespace_owner,
      audit_log_queries: audit_log_queries,
    }
  end

  def create
    result = RetiredNamespace.retire(owner: namespace_owner, name: params[:name])

    if result.success?
      flash[:notice] = "Retired #{result.namespace.name_with_owner}"
    else
      flash[:error] = "Retiring namespace failed: #{result.errors.to_sentence}"
    end

    redirect_to stafftools_user_retired_namespaces_path(namespace_owner)
  end

  def destroy
    result = this_namespace.unretire

    if result.success?
      flash[:notice] = "Unretired #{this_namespace.name_with_owner}"
    else
      flash[:error] = "Unretiring namespace failed: #{result.errors.to_sentence}"
    end

    redirect_to stafftools_user_retired_namespaces_path(namespace_owner)
  end

  private

  def retired_namespaces_layout
    if this_user.present?
      overview_layout
    end
  end

  def ensure_this_namespace
    return render_404 unless this_namespace.present?
  end

  def namespace_owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @namespace_owner if defined?(@namespace_owner)
    @namespace_owner = this_user.present? ? this_user : params[:user_id]
  end

  def this_namespace # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_namespace if defined?(@this_namespace)
    login = namespace_owner.is_a?(User) ? namespace_owner.login : namespace_owner

    @this_namespace = RetiredNamespace.find_by(
      id: params[:id],
      owner_login: login,
    )
  end
end
