# typed: true
# frozen_string_literal: true

class Businesses::GlobalBusinessRedirectController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :login_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1, only: %i(show)

  def show
    redirect_to "/enterprises/#{GitHub.global_business}/#{params[:route]}"
  end
end
