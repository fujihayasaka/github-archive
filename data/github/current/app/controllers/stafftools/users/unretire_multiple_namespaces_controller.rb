# typed: true
# frozen_string_literal: true

class Stafftools::Users::UnretireMultipleNamespacesController < Stafftools::Users::RetiredNamespacesController
  skip_before_action :ensure_this_namespace, only: :destroy

  def destroy
    ids = JSON.parse(params[:retired_namespace][:ids])
    result = RetiredNamespace.unretire_multiple(user: namespace_owner, ids: ids)

    if result.success?
      flash[:notice] = "Unretired multiple namespaces owned by #{namespace_owner}"
    else
      flash[:error] = "Unretiring namespace failed: #{result.errors.to_sentence}"
    end

    redirect_to stafftools_user_retired_namespaces_path(namespace_owner)
  end
end
