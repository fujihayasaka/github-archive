# typed: true
# frozen_string_literal: true

class Stafftools::Users::SamlMappingController < Stafftools::UsersController

  def update
    name_id = params[:name_id]

    if saml_mapping.blank?
      flash[:error] = "This user doesn't have a SAML mapping to update."
    else
      if saml_mapping.update(name_id: name_id)
        flash[:notice] = "NameID updated for #{this_user}."
      else
        error_message = saml_mapping.errors[:name_id].join(", ")
        flash[:error] = "Error updating NameID: NameID #{error_message}"
      end
    end

    redirect_to stafftools_user_security_path(this_user)
  end

  private

  memoize def saml_mapping
    this_user.saml_mapping
  end
end
