# typed: true
# frozen_string_literal: true

class Biztools::Users::EducationTermsController < BiztoolsController
  before_action :ensure_user_exists

  def create
    current_account.terms_of_service.enable_esa_education_upgrade_prompt
    flash[:notice] = "Enabled Education Terms of Service prompt"
    redirect_to "/biztools/users/#{current_account}"
  end
end
