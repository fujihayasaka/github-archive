# typed: true
# frozen_string_literal: true

class Stafftools::SafeguardLimitsController < StafftoolsController
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    if request_for_business?
      render "stafftools/safeguard_limits/index",
        layout: "layouts/stafftools/business",
        locals: { limits_target: limits_target }
    else
      render "stafftools/safeguard_limits/index",
        layout: "stafftools",
        locals: { limits_target: limits_target }
    end
  end

  private

  def request_for_business?
    this_business.present?
  end

  memoize def this_business
    return unless params[:slug].present?
    Business.find_by(slug: params[:slug])
  end
  helper_method :this_business

  def limits_target
    if this_business.present?
      this_business
    else
      GitHub
    end
  end
end
