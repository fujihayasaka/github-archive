# typed: strict
# frozen_string_literal: true

module Stafftools::Users::ControllerLayoutMethods
  extend T::Sig
  extend T::Helpers

  requires_ancestor { StafftoolsController }

  sig { returns(String) }
  def content_layout
    if this_user.site_admin_context == "organization"
      "layouts/stafftools/organization/content"
    else
      "layouts/stafftools/user/content"
    end
  end

  sig { returns(String) }
  def overview_layout
    if this_user.site_admin_context == "organization"
      "layouts/stafftools/organization/overview"
    else
      "layouts/stafftools/user/overview"
    end
  end

  sig { returns(String) }
  def billing_layout
    if this_user.site_admin_context == "organization"
      "layouts/stafftools/organization/billing"
    else
      "layouts/stafftools/user/billing"
    end
  end

  sig { returns(String) }
  def security_layout
    if this_user.site_admin_context == "organization"
      "layouts/stafftools/organization/security"
    else
      "layouts/stafftools/user/security"
    end
  end
end
